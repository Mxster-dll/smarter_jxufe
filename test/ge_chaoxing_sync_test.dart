/// 分数估计 · 学习通作业成绩接入（课程名匹配 / 作业均分 / 同步口径）单元测试。
///
/// 用户口径（2026-09-22）：「我们希望把学习通中的各课程作业成绩接入『分数估计』，
/// 但**前提是该课程给出了作业的占比**」→ 判定与边界见
/// `lib/features/score_estimate/domain/ge_chaoxing_sync.dart` 的文件头。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_course.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_snapshot.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_chaoxing_works.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_chaoxing_sync.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_engine.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_models.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

// ---- 构造件 ----

ChaoxingCourse cc(String courseId, String name, {String classId = 'k1'}) =>
    ChaoxingCourse(
      courseId: courseId,
      classId: classId,
      cpi: '900000001',
      name: name,
    );

ChaoxingWork work(
  String courseId,
  String workId, {
  double? score,
  ChaoxingWorkStatus status = ChaoxingWorkStatus.done,
  DateTime? dueAt,
}) => ChaoxingWork(
  workId: workId,
  title: '作业 $workId',
  courseId: courseId,
  courseName: '',
  status: status,
  score: score,
  dueAt: dueAt,
);

ChaoxingSnapshot snap(
  List<ChaoxingCourse> courses,
  List<ChaoxingWork> works, {
  DateTime? fetchedAt,
}) => ChaoxingSnapshot(courses: courses, works: works, fetchedAt: fetchedAt);

GePart part({
  String id = 'p1',
  String name = '作业',
  GePartMode mode = GePartMode.score,
  int target = 100,
  int current = 0,
  double score = 0,
  double cap = 15,
  String note = '',
  String source = '',
}) => GePart(
  id: id,
  name: name,
  mode: mode,
  target: target,
  current: current,
  score: score,
  cap: cap,
  note: note,
  source: source,
);

GeCourse course({
  String name = '线性代数(工)',
  double dailyPercent = 30,
  required List<GePart> parts,
}) => GeCourse(id: 'g1', name: name, dailyPercent: dailyPercent, parts: parts);

/// 平时 30 分 = 考勤 5 + 作业 15 + 表现 10（作业占平时 50%）。
List<GePart> stdParts({String homeworkSource = ''}) => [
  part(id: 'kq', name: '考勤', mode: GePartMode.down, target: 16, current: 16, cap: 5),
  part(cap: 15, source: homeworkSource),
  part(id: 'bx', name: '表现', target: 10, current: 5, cap: 10),
];

void main() {
  group('课程名归一（教务名 ↔ 学习通名）', () {
    test('去学期前缀 / 裸数字前缀', () {
      expect(geNormalizeCourseName('261学期 线性代数(工)'), '线性代数(工)');
      expect(geNormalizeCourseName('261学期线性代数(工)'), '线性代数(工)');
      expect(geNormalizeCourseName('253程序设计实训'), '程序设计实训');
    });

    test('全角括号 / 空白 / 大小写 / 间隔号统一', () {
      expect(geNormalizeCourseName('大学英语（读写）'), '大学英语(读写)');
      expect(geNormalizeCourseName(' Data  Structure '), 'datastructure');
      expect(geNormalizeCourseName('面向对象（双语）'), '面向对象(双语)');
      expect(geNormalizeCourseName('计算·机'), '计算机');
    });
  });

  group('学习通课程匹配', () {
    test('全等优先于包含匹配', () {
      final courses = [cc('1', '261学期 线性代数'), cc('2', '261学期 线性代数(工)')];
      final hit = geMatchChaoxingCourses(courses, '线性代数');
      expect(hit.map((c) => c.courseId), ['1']);
    });

    test('包含匹配：教务名是学习通名的子串', () {
      final hit = geMatchChaoxingCourses([cc('9', '261学期 线性代数(工)')], '线性代数');
      expect(hit.map((c) => c.courseId), ['9']);
    });

    test('对不上 → 空（宁可不要，也不猜错课）', () {
      expect(geMatchChaoxingCourses([cc('1', '261学期 线性代数')], '高等数学'), isEmpty);
      expect(geMatchChaoxingCourses(const [], '线性代数'), isEmpty);
      expect(geMatchChaoxingCourses([cc('1', '线性代数')], '  '), isEmpty);
    });

    test('多门命中：取已评分作业最多的那门，并合并同学期教学班', () {
      final courses = [
        cc('11', '261学期 程序设计实训', classId: 'a'),
        cc('12', '261学期 程序设计实训', classId: 'b'),
        cc('25', '252学期 程序设计实训', classId: 'a'),
      ];
      final scored = {
        '11': [work('11', 'w1')],
        '12': [work('12', 'w2')],
        '25': [work('25', 'w3'), work('25', 'w4'), work('25', 'w5')],
      };
      // 252 学期那门作业最多 → 选它（只同 term 合并 → 只有它一条）。
      expect(
        geMatchChaoxingCourses(courses, '程序设计实训', scored: scored)
            .map((c) => c.courseId),
        ['25'],
      );
      // 去掉跨学期干扰：同学期两个教学班合并。
      final merged = geMatchChaoxingCourses(
        courses.sublist(0, 2),
        '程序设计实训',
        scored: scored,
      );
      expect(merged.map((c) => c.courseId), ['11', '12']);
    });
  });

  group('作业均分（只认已完成且有分数）', () {
    test('均分 = 已批作业分数的算术平均，条数如实', () {
      final s = snap([cc('1', '261学期 线性代数(工)')], [
        work('1', 'a', score: 90),
        work('1', 'b', score: 85),
        work('1', 'c', score: 100),
      ]);
      final hw = geChaoxingHomeworkFor(s, '线性代数(工)')!;
      expect(hw.count, 3);
      expect(hw.average, closeTo((90 + 85 + 100) / 3, 1e-9));
      expect(hw.courseName, '线性代数(工)');
    });

    test('待做 / 待批阅 / 无分数一律不算（否则会把「还没批」当成 0 分）', () {
      final s = snap([cc('1', '线性代数(工)')], [
        work('1', 'a', score: 90),
        work('1', 'b', status: ChaoxingWorkStatus.todo, score: 100),
        work('1', 'c', status: ChaoxingWorkStatus.pendingReview, score: 0),
        work('1', 'd'),
        work('1', 'e', status: ChaoxingWorkStatus.unknown, score: 60),
      ]);
      final hw = geChaoxingHomeworkFor(s, '线性代数')!;
      expect(hw.count, 1);
      expect(hw.average, closeTo(90, 1e-9));
    });

    test('越界分 clamp 到 0~100；多教学班按 workId 去重', () {
      final s = snap(
        [
          cc('1', '261学期 线性代数(工)', classId: 'a'),
          cc('2', '261学期 线性代数(工)', classId: 'b'),
        ],
        [
          work('1', 'a', score: 120),
          work('2', 'a', score: 120), // 同一份作业的两个教学班副本
          work('2', 'b', score: 80),
        ],
      );
      final hw = geChaoxingHomeworkFor(s, '线性代数(工)')!;
      expect(hw.count, 2);
      expect(hw.average, closeTo(90, 1e-9)); // (100 + 80) / 2
      expect(hw.courseIds.length, 2);
    });

    test('没缓存 / 名字对不上 / 没有已批作业 → null', () {
      expect(geChaoxingHomeworkFor(null, '线性代数'), isNull);
      expect(geChaoxingHomeworkFor(ChaoxingSnapshot.empty, '线性代数'), isNull);
      final s = snap([cc('1', '261学期 线性代数(工)')], [
        work('1', 'a', status: ChaoxingWorkStatus.todo),
      ]);
      expect(geChaoxingHomeworkFor(s, '线性代数(工)'), isNull);
      expect(geChaoxingHomeworkFor(s, '大学英语'), isNull);
    });
  });

  group('同步口径：只有该课给出了作业占比才接（用户 2026-09-22）', () {
    test('没有「作业」分项 → 不接入（占比未知，绝不替用户造分项）', () {
      final c = course(parts: [
        part(id: 'kq', name: '考勤', mode: GePartMode.down, target: 16, current: 16, cap: 5),
      ]);
      expect(geHomeworkPartOf(c), isNull);
      expect(geApplyChaoxingHomework(c, average: 92.5, workCount: 4), isNull);
    });

    test('「作业」分项分值上限为 0 → 不算给出了占比', () {
      final c = course(parts: [part(name: '作业', cap: 0)]);
      expect(geHomeworkPartOf(c), isNull);
      expect(geApplyChaoxingHomework(c, average: 92.5, workCount: 4), isNull);
    });

    test('直接分数型的「作业」分项 → 自动接管（满分 100、均值写入、来源标记）', () {
      final c = course(parts: stdParts());
      final r = geApplyChaoxingHomework(c, average: 92.5, workCount: 4)!;
      expect(r.adopted, isTrue);
      final p = r.part;
      expect(p.mode, GePartMode.score);
      expect(p.target, 100);
      expect(p.score, closeTo(92.5, 1e-9));
      expect(p.source, gePartSourceChaoxing);
      // 结构与占比一律不动
      expect(p.cap, 15);
      expect(p.name, '作业');
      expect(p.id, 'p1');
      expect(r.course.parts.length, 3);
      // 折算：得分率 92.5% × 15 = 13.875
      expect(gePartScore(p), closeTo(13.875, 1e-9));
    });

    test('计数型的「作业提交」不静默改写；用户点「接入」(force) 才改成直接分数', () {
      final c = course(parts: [
        part(id: 'hw', name: '作业提交', mode: GePartMode.up, target: 20, current: 12, cap: 15),
      ]);
      expect(geApplyChaoxingHomework(c, average: 92.5, workCount: 4), isNull);

      final r = geApplyChaoxingHomework(
        c,
        average: 92.5,
        workCount: 4,
        force: true,
      )!;
      expect(r.part.mode, GePartMode.score);
      expect(r.part.target, 100);
      expect(r.part.score, closeTo(92.5, 1e-9));
      expect(r.part.cap, 15); // 占比不变
      expect(r.part.name, '作业提交'); // 名字是用户的
      expect(r.part.current, 12); // 计数留着，改回计数型还在
    });

    test('幂等：值没变就不返回结果（进页面不反复写库）', () {
      final c = course(parts: stdParts(homeworkSource: gePartSourceChaoxing));
      final first = geApplyChaoxingHomework(c, average: 92.5, workCount: 4)!;
      expect(first.adopted, isFalse);
      expect(
        geApplyChaoxingHomework(first.course, average: 92.5, workCount: 4),
        isNull,
      );
      // 均分变了 → 更新
      final again =
          geApplyChaoxingHomework(first.course, average: 88, workCount: 5)!;
      expect(again.part.score, closeTo(88, 1e-9));
    });

    test('已接入的分项改了名照样认（source 优先）', () {
      final c = course(parts: [
        part(name: '平时作业（学习通）', source: gePartSourceChaoxing),
      ]);
      expect(geHomeworkPartOf(c)?.name, '平时作业（学习通）');
    });

    test('关掉开关（manual）后不再自动接管', () {
      final c = course(parts: stdParts(homeworkSource: gePartSourceManual));
      expect(geHomeworkPartOf(c), isNull);
      expect(geApplyChaoxingHomework(c, average: 92.5, workCount: 4), isNull);
    });

    test('均值非法 / 没有已批作业 → 不写', () {
      final c = course(parts: stdParts());
      expect(geApplyChaoxingHomework(c, average: null, workCount: 3), isNull);
      expect(geApplyChaoxingHomework(c, average: 90, workCount: 0), isNull);
      expect(
        geApplyChaoxingHomework(c, average: double.nan, workCount: 3),
        isNull,
      );
    });

    test('越界均分写入前 clamp 到 0~100', () {
      final c = course(parts: stdParts());
      final r = geApplyChaoxingHomework(c, average: 130, workCount: 2)!;
      expect(r.part.score, 100);
    });
  });

  group('占比（分值份额）', () {
    test('平时占比 = cap / Σcap；总评占比再乘平时占比', () {
      final c = course(dailyPercent: 30, parts: stdParts());
      final hw = geHomeworkPartOf(c)!;
      expect(gePartDailyShare(c, hw), closeTo(50, 1e-9));
      expect(gePartTotalShare(c, hw), closeTo(15, 1e-9));
    });

    test('分项分值全为 0 → 0%（不除零）', () {
      final c = course(parts: [part(name: '作业', cap: 0)]);
      expect(gePartDailyShare(c, c.parts.first), 0);
    });

    test('同步结果自带占比（界面文案用）', () {
      final c = course(parts: stdParts());
      final r = geApplyChaoxingHomework(c, average: 92.5, workCount: 4)!;
      expect(r.dailyShare, closeTo(50, 1e-9));
      expect(r.totalShare, closeTo(15, 1e-9));
      expect(r.workCount, 4);
    });
  });

  group('分项名识别', () {
    test('像作业的名字', () {
      for (final n in ['作业', '作业提交', '平时作业', 'Homework', 'Assignment 1']) {
        expect(gePartNameLooksLikeHomework(n), isTrue, reason: n);
      }
    });

    test('不像作业的名字（含刻意不认 hw 缩写的理由）', () {
      for (final n in ['考勤', '期中测验', '实验报告', '课堂表现', 'shw', '']) {
        expect(gePartNameLooksLikeHomework(n), isFalse, reason: n);
      }
    });
  });

  group('GePart.source 往返与容错', () {
    test('toJson / fromJson 保留来源标记', () {
      final p = part(source: gePartSourceChaoxing);
      final back = GePart.fromJson(p.toJson());
      expect(back.source, gePartSourceChaoxing);
    });

    test('旧缓存没有 source 字段 → 手填（可被自动接管）', () {
      final raw = part().toJson()..remove('source');
      expect(GePart.fromJson(raw).source, '');
    });

    test('copyWith 不带 source 时保留原值', () {
      final p = part(source: gePartSourceChaoxing);
      expect(p.copyWith(cap: 20).source, gePartSourceChaoxing);
      expect(p.copyWith(source: '').source, '');
    });
  });

  group('界面小件（ge_common）', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('说明行：文案上屏；不给 onBind 就不画「接入」按钮', (tester) async {
      await tester.pumpWidget(host(const GeChaoxingNotice(text: '占比未知，没有接入')));
      expect(find.text('占比未知，没有接入'), findsOneWidget);
      expect(find.text('接入'), findsNothing);
    });

    testWidgets('说明行：给了 onBind 才画按钮，点击回调一次', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(GeChaoxingNotice(text: '接入会覆盖计数', onBind: () => taps++)),
      );
      expect(find.text('接入'), findsOneWidget);
      await tester.tap(find.text('接入'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('来源芯片：文案固定，hint 进 Tooltip', (tester) async {
      await tester.pumpWidget(
        host(const GeChaoxingChip(hint: '作业均分来自学习通（2026-09-20 23:26）')),
      );
      expect(find.text('学习通同步'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_sync_outlined), findsOneWidget);
      final tip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tip.message, contains('2026-09-20 23:26'));
    });

    testWidgets('来源芯片：hint 为空则不挂 Tooltip', (tester) async {
      await tester.pumpWidget(host(const GeChaoxingChip()));
      expect(find.text('学习通同步'), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
    });
  });

  group('源码守卫', () {
    String read(String path) => File(path).readAsStringSync();

    test('来源常量只有一处定义（chaoxing / manual）', () {
      final hits = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final path = f.path.replaceAll('\\', '/');
        if (path.contains('/old/')) continue;
        final src = f.readAsStringSync();
        if (src.contains('const String gePartSourceChaoxing =') ||
            src.contains('const String gePartSourceManual =')) {
          hits.add(path);
        }
      }
      expect(hits, ['lib/features/score_estimate/domain/ge_chaoxing_sync.dart']);
    });

    test('课程详情页在进页面时自动同步，且用领域层唯一入口', () {
      final src = read(
        'lib/features/score_estimate/presentation/course_detail_screen.dart',
      );
      expect(src.contains('await _syncChaoxingHomework();'), isTrue);
      expect(src.contains('geApplyChaoxingHomework('), isTrue);
      expect(src.contains('geChaoxingSnapshotProvider'), isTrue);
      // 改分项 / 改课后立刻重对一次（否则用户得「退出再进」才生效）：3 个调用点。
      final hooks = RegExp(r'_resyncChaoxing\(\);').allMatches(src).length;
      expect(hooks, greaterThanOrEqualTo(3), reason: '加/改分项、改名各一处');
    });

    test('取数层不发学习通请求（超星有请求配额，只准读缓存）', () {
      final src = read('lib/features/score_estimate/data/ge_chaoxing_works.dart');
      expect(src.contains('chaoxing_store.dart'), isTrue);
      expect(src.contains("import 'package:dio"), isFalse);
      expect(src.contains('Dio('), isFalse);
    });
  });
}
