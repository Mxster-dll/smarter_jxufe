/// 课表类 AI 工具的**学期维度**（2026-09-27）。
///
/// 背景（用户原话）：「为什么app内ai提示只能查本学期课表，但是我们明明是有查各学期
/// 课表的能力的」—— 能力在数据层一直是全的：教务端点吃任意学期
/// （`schedule_remote_datasource.dart` 的 `xn=$year&xq=$semester&xh=$studentId`）、
/// 缓存键按学期分（`schedule_cache_repository.dart` 的
/// `schedule|$year|$semester|$studentId`）、按学期取数的 provider family 也在
/// （`schedule_display_providers.dart` 的 `scheduleCachedEntriesProvider`），
/// 课表页的学年 / 学段选择器一直在用它们。**写死的是 AI 工具层**：
/// `loadMySchedule` 没有学期参数、`get_my_schedule` / `query_timetable` /
/// `find_free_time` 的参数表里没有学期，公共查询那边还把学期钉在「当下学期那一项」。
///
/// 本文件守三条：
/// 1. 三个工具都吃 `xn`（学年起始年）+ `xq`（0 第一 / 1 第二）；
/// 2. **不传学期 = 当下学期**（旧行为一个字都不许变）；
/// 3. 查非本学期时**不拿当下学期的教学周 /「今天」**去过滤或贴标签
///    （把 261 的第 3 周当成 252 的第 3 周，是这类改动最容易引入的错）。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/core/network/schedule_repository.dart';
import 'package:smarter_jxufe/features/ai/data/ai_snapshot.dart';
import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/ai/tools/my_schedule_data.dart';
import 'package:smarter_jxufe/features/ai/tools/schedule_tools.dart';
import 'package:smarter_jxufe/features/ai/tools/timetable_tools.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_providers.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_display_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/school_calendar/data/wxcal_repository.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';

/// `now` 固定在这一天：离线校历里它属于 **2026-2027 学年第一学期**（= 当下学期）。
final _now = DateTime(2026, 10, 15, 14, 30);

/// 借一个返回自身的 Provider 把真实 `Ref` 取出来（同 `ai_tools_test.dart`）。
AiToolContext contextWith(ProviderContainer container) => AiToolContext(
  ref: container.read(Provider<Ref>((ref) => ref)),
  gate: const AiDenyWriteGate(),
  now: _now,
);

/// 只在第 [startWeek]-[endWeek] 周上的课（用来验「非本学期不被当下教学周过滤」）。
ScheduleEntry entry({int startWeek = 1, int endWeek = 2}) => ScheduleEntry(
  classCode: '001567-056',
  className: '主干+',
  courseCode: '1004600282',
  courseName: '大学英语II',
  totalHours: 64,
  credits: 4,
  studyNature: '初修',
  teacherCode: '1200000001',
  teacherName: '[TEACHER_P]',
  selectionStatus: '选中',
  isCrossMajor: false,
  hasTextbook: true,
  classTimes: [
    ClassTime(
      startWeek: startWeek,
      endWeek: endWeek,
      weekParity: WeekParity.every,
      dayOfWeek: DayOfWeek.thursday,
      startPeriod: 1,
      endPeriod: 2,
      classroom: '麦三教3407',
    ),
  ],
);

/// 当下学期（261）的第 3 教学周 —— 与上面那门 1-2 周的课**刻意错开**。
TeachingWeek teachingWeek3() {
  final terms = wxcalOfflineToDomain();
  final term = terms.firstWhere(
    (t) => t.term == '261',
    orElse: () => terms.last,
  );
  return TeachingWeek(
    week: 3,
    firstMonday: DateTime(2026, 9, 7),
    weekMonday: DateTime(2026, 9, 21),
    term: term,
  );
}

/// 假课表仓库：只记下「被传进来的学期参数」并回固定条目（**不碰网络**）。
class _FakeScheduleRepository implements ScheduleRepository {
  _FakeScheduleRepository([this.result = const []]);

  final List<ScheduleEntry> result;
  final List<String> calls = [];

  @override
  Future<List<ScheduleEntry>> getSchedule({
    required String year,
    required String semester,
    required String studentId,
  }) async {
    calls.add('$year|$semester|$studentId');
    return result;
  }
}

/// 学期相关的 override 都拢在这里：账号 + 缓存（记录被问到的学期）+ 教学周。
ProviderContainer containerWith({
  List<({int xn, int xq})>? asked,
  List<ScheduleEntry>? cached,
  ScheduleRepository? online,
  TeachingWeek? teachingWeek,
}) => ProviderContainer(
  overrides: [
    currentAccountProvider.overrideWith((ref) => '2000000000'),
    scheduleCachedEntriesProvider.overrideWith((ref, arg) async {
      asked?.add(arg);
      return cached ?? const <ScheduleEntry>[];
    }),
    if (online != null)
      scheduleRepositoryProvider.overrideWith((ref) async => online),
    teachingWeekProvider.overrideWith((ref) async => teachingWeek),
  ],
);

void main() {
  // 工具跑到底会顺手读作息表（`cachedPeriodTableProvider` → Hive `periodTable` box，
  // 纯 `Box<String>` 无需 adapter）——不初始化就是一个没人处理的 HiveError，
  // 会把「课表读到了」的用例整个打红。临时目录开一次即可，用完删掉。
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('sjx_ai_term_test');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
  });

  group('aiTermArg · 学期参数归一', () {
    test('两个都不给 → null（= 用当下学期）', () {
      final container = containerWith();
      addTearDown(container.dispose);
      final ctx = contextWith(container);

      final a = AiArgs(const {});
      expect(aiTermArg(ctx, a), isNull);
      expect(a.hasError, isFalse);
      // 2026-10-15 落在离线校历的 261 学期区间内
      expect(aiCurrentTerm(ctx), (xn: 2026, xq: 0));
    });

    test('只给 xn → 学段补当下学期的值（模型常只给学年）', () {
      final container = containerWith();
      addTearDown(container.dispose);

      expect(aiTermArg(contextWith(container), AiArgs({'xn': 2025})), (
        xn: 2025,
        xq: 0,
      ));
    });

    test('越界的学年 / 学段 → 记参数错误并拒绝，不按不存在的学期去拉数据', () {
      final container = containerWith();
      addTearDown(container.dispose);
      final ctx = contextWith(container);

      final badXn = AiArgs({'xn': 1999});
      expect(aiTermArg(ctx, badXn), isNull);
      expect(badXn.hasError, isTrue);
      expect(badXn.errorText, contains('xn'));

      final badXq = AiArgs({'xq': 5});
      expect(aiTermArg(ctx, badXq), isNull);
      expect(badXq.hasError, isTrue);
      expect(badXq.errorText, contains('xq'));
    });
  });

  group('loadMySchedule · 学期', () {
    test('★ 给了 xn/xq → 就去读那一学期的缓存（键跟着换）', () async {
      final asked = <({int xn, int xq})>[];
      final container = containerWith(asked: asked, cached: [entry()]);
      addTearDown(container.dispose);

      final data = await loadMySchedule(
        contextWith(container),
        xn: 2025,
        xq: 0,
      );
      expect(asked, [(xn: 2025, xq: 0)]);
      expect(data.term, (xn: 2025, xq: 0));
      expect(myTermLabel(data.term), '2025-2026学年第一学期');
      expect(data.fromCache, isTrue);
      expect(data.entries.single.courseName, '大学英语II');
    });

    test('不给学期 → 仍是当下学期（旧行为回归）', () async {
      final asked = <({int xn, int xq})>[];
      final container = containerWith(asked: asked, cached: [entry()]);
      addTearDown(container.dispose);

      final data = await loadMySchedule(contextWith(container));
      expect(asked, [(xn: 2026, xq: 0)]);
      expect(myTermLabel(data.term), '2026-2027学年第一学期');
    });

    test('过去学期没有缓存 → 联网，且 year / semester 原样传给教务', () async {
      final fake = _FakeScheduleRepository([entry()]);
      final container = containerWith(online: fake);
      addTearDown(container.dispose);

      final data = await loadMySchedule(
        contextWith(container),
        xn: 2025,
        xq: 1,
      );
      expect(fake.calls, ['2025|1|2000000000']);
      expect(data.fromCache, isFalse);
      expect(data.entries.single.courseName, '大学英语II');
    });
  });

  group('get_my_schedule · 学期参数', () {
    test('★ 传 xn/xq → 真去查那一学期（用户问的那件事）', () async {
      final asked = <({int xn, int xq})>[];
      final container = containerWith(asked: asked, cached: [entry()]);
      addTearDown(container.dispose);

      final r = await const GetMyScheduleTool().run(contextWith(container), {
        'xn': 2025,
        'xq': 0,
      });
      expect(r.ok, isTrue);
      expect(asked, [(xn: 2025, xq: 0)]);
      expect(r.content, contains('学期：2025-2026学年第一学期'));
      // 非本学期默认按整学期列（「今天」对别的学期没有意义）
      expect(r.content, contains('范围：整学期'));
      expect(r.content, contains('大学英语II'));
      expect(r.content, contains('[TEACHER_P]'));
    });

    test('不传学期 → 当下学期 + 默认「今天」（旧行为回归）', () async {
      final asked = <({int xn, int xq})>[];
      final container = containerWith(asked: asked, cached: [entry()]);
      addTearDown(container.dispose);

      final r = await const GetMyScheduleTool().run(
        contextWith(container),
        const {},
      );
      expect(asked, [(xn: 2026, xq: 0)]);
      expect(r.content, contains('学期：2026-2027学年第一学期'));
      expect(r.content, contains('范围：今天'));
    });

    test('★ 查过去学期时不被「当前教学周」过滤（第 3 周不该滤掉 1-2 周的课）', () async {
      final container = containerWith(
        cached: [entry()],
        teachingWeek: teachingWeek3(),
      );
      addTearDown(container.dispose);
      final ctx = contextWith(container);

      // 对照组：当下学期 + 本周 → 这门课确实被滤掉（说明过滤本身还在）
      final now = await const GetMyScheduleTool().run(ctx, {'scope': 'week'});
      expect(now.content, contains('第 3 教学周'));
      expect(now.content, contains('这段时间没有课'));

      // 正题：换成过去学期 → 教学周不该参与，整学期一门都不能少
      final past = await const GetMyScheduleTool().run(ctx, {
        'xn': 2025,
        'xq': 0,
      });
      expect(past.content, contains('大学英语II'));
    });

    test('指定学期查不到 → 文案里给「可选学期」，不是一个干巴巴的「空的」', () async {
      final container = containerWith(online: _FakeScheduleRepository());
      addTearDown(container.dispose);

      final r = await const GetMyScheduleTool().run(contextWith(container), {
        'xn': 2019,
        'xq': 0,
      });
      expect(r.ok, isTrue);
      expect(r.content, contains('2019-2020学年第一学期'));
      expect(r.content, contains('可选学期：'));
      expect(r.content, contains('xn=2026，xq=0'));
      expect(r.content, contains('本学期'));
    });
  });

  group('公共查询 · 学期', () {
    const terms = [
      PublicQueryTerm(xn: 2026, xqM: 0, name: '2026-2027学年第一学期'),
      PublicQueryTerm(xn: 2025, xqM: 1, name: '2025-2026学年第二学期'),
      PublicQueryTerm(xn: 2025, xqM: 0, name: '2025-2026学年第一学期'),
    ];

    ProviderContainer withTerms() => ProviderContainer(
      overrides: [
        publicQueryTermsProvider.overrideWith((ref) async => terms),
        teachingWeekProvider.overrideWith((ref) async => null),
      ],
    );

    test('★ 指定 xn/xq → 用那一项（此前恒取「当下学期那一项」）', () async {
      final container = withTerms();
      addTearDown(container.dispose);

      final term = await resolvePublicQueryTerm(
        contextWith(container),
        xn: 2025,
        xq: 1,
      );
      expect(term.name, '2025-2026学年第二学期');
      expect(term.code, '2025,1');
    });

    test('不给学期 → 当下学期那一项（旧行为回归）', () async {
      final container = withTerms();
      addTearDown(container.dispose);

      final term = await resolvePublicQueryTerm(contextWith(container));
      expect(term.name, '2026-2027学年第一学期');
    });

    test('教务没有这个学期 → 抛错并列出可选学期（让模型换值重试）', () async {
      final container = withTerms();
      addTearDown(container.dispose);

      await expectLater(
        resolvePublicQueryTerm(contextWith(container), xn: 2019, xq: 0),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('可选学期'))
              .having(
                (e) => e.message,
                'message',
                contains('2025-2026学年第一学期（xn=2025，xq=0）'),
              ),
        ),
      );
    });
  });

  group('工具 schema 真的暴露了学期', () {
    const tools = [GetMyScheduleTool(), QueryTimetableTool(), FindFreeTimeTool()];

    test('三个课表类工具的 parameters 里都有 xn / xq', () {
      for (final tool in tools) {
        final props =
            (tool.spec.parameters['properties'] as Map).keys.toSet();
        expect(props, containsAll(<String>['xn', 'xq']), reason: tool.spec.name);
      }
    });

    test('描述里写清「默认当下学期 + 别的学期传 xn/xq」', () {
      for (final tool in tools) {
        expect(tool.spec.description, contains('xn'), reason: tool.spec.name);
        expect(
          tool.spec.description,
          contains('当下学期'),
          reason: tool.spec.name,
        );
      }
    });
  });

  group('快照与系统提示词', () {
    test('★ 快照带上学期参数与可选学期（模型不必先试错一轮）', () async {
      final container = ProviderContainer(
        overrides: [
          teachingWeekProvider.overrideWith((ref) async => teachingWeek3()),
          // 快照里学籍那块是守卫过的可选行，这里直接让它失败，免碰 Hive
          studentInfoRepositoryProvider.overrideWith(
            (ref) async => throw Exception('测试不读学籍'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final snap = await buildAiSnapshot(
        container.read(Provider<Ref>((ref) => ref)),
        now: _now,
      );
      expect(snap, contains('学期：2026-2027学年第一学期（xn=2026，xq=0）'));
      expect(snap, contains('第 3 教学周'));
      expect(snap, contains('可选学期：'));
      expect(snap, contains('xn=2025')); // 上一学年就在清单里
      expect(snap, contains('本学期'));
    });

    test('提示词里有跨学期路由规则（工具加了参数，规则不说模型照样只答本学期）', () {
      final prompt = aiSystemPrompt(toolsEnabled: true);
      expect(prompt, contains('上一学年'));
      expect(prompt, contains('`xn`'));
      expect(prompt, contains('`xq`'));
      expect(prompt, contains('别的学期'));
    });
  });
}
