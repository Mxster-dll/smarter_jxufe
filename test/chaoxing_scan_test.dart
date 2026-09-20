/// 学习通「只扫当下学期」与「通知里的作业提醒」的守卫（2026-09-20 用户选定 A+B）。
///
/// A = 只扫当下学期：作业是学习通里**唯一没有统一接口**的数据（逐课 2 请求，
///     35 门 = 70 个请求必然撞风控 ≈60/窗口），所以真正的解法不是分批轮转而是缩小范围。
/// B = 用通知兜底：通知是统一接口（1 请求），平台发布作业时自动发 `作业:《课程名》标题`。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_course.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_notice.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_scan.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_snapshot.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_text.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';

ChaoxingCourse _course(String id, String name) =>
    ChaoxingCourse(courseId: id, classId: '2$id', cpi: '9', name: name);

void main() {
  group('课程学期码（口径必须与 school_term.dart 的 schoolTermCode 一致）', () {
    test('前缀 `261学期` → 261；无前缀 → 空串（不硬造）', () {
      expect(_course('1', '261学期 线性代数(工)').termCode, '261');
      expect(_course('2', '252学期 程序设计实践').termCode, '252');
      expect(_course('3', '253程序设计实训').termCode, '', reason: '缺 `学期` 二字，认不出');
      expect(_course('4', '大学生国家安全教育').termCode, '');
      expect(_course('5', ' 261学期 数据结构').termCode, '261', reason: '首尾空白要容忍');
    });
  });

  group('★ A：只扫当下学期（用户 2026-09-20 选定）', () {
    final courses = [
      _course('1', '261学期 线性代数(工)'),
      _course('2', '252学期 程序设计实践'),
      _course('3', '253程序设计实训'),
      _course('4', '大学生国家安全教育'),
      _course('5', '251学期 计算机科学导论'),
    ];

    test('当下学期 + 学期认不出的课都扫，往期课剔除', () {
      final targets = chaoxingScanTargets(courses, currentTermCode: '261');
      expect(targets.map((c) => c.courseId).toList(), ['1', '3', '4'],
          reason: '顺序保持课程页原顺序（分批窗口才不会跳）');
    });

    test('往期课进 skipped（界面据此如实标注，不能说「下次进入补扫」）', () {
      final skipped = chaoxingSkippedCourses(courses, currentTermCode: '261');
      expect(skipped.map((c) => c.courseId).toList(), ['2', '5']);
    });

    test('两组**严格互补**：没有课既在扫描范围又在跳过名单里', () {
      for (final code in ['261', '252', '251', '']) {
        final targets = chaoxingScanTargets(courses, currentTermCode: code).toSet();
        final skipped = chaoxingSkippedCourses(courses, currentTermCode: code).toSet();
        expect(targets.intersection(skipped), isEmpty);
        expect(targets.union(skipped).length, courses.length);
      }
    });

    test('当下学期码为空（判不出学期）→ 不筛，全扫', () {
      expect(
        chaoxingScanTargets(courses, currentTermCode: '').length,
        courses.length,
      );
      expect(chaoxingSkippedCourses(courses, currentTermCode: ''), isEmpty);
    });

    test('学期码认不出的课**照扫**（为省 4 个请求漏掉一门真在上的课不划算）', () {
      final t = chaoxingScanTargets(courses, currentTermCode: '261')
          .map((c) => c.name)
          .toList();
      expect(t, contains('253程序设计实训'));
      expect(t, contains('大学生国家安全教育'));
    });

    test('★ 一门课都不匹配当下学期码 → **不筛**（新学期课程还没建时别把界面变成全空）', () {
      // 例如暑假里 262 学期的课还没导入：若照筛，25 门往期课全被判「非当下学期」，
      // 用户会看到「一条作业都没有」——比多花请求糟得多。
      final plan = chaoxingScanPlan(courses, currentTermCode: '262');
      expect(plan.targets.length, courses.length);
      expect(plan.skipped, isEmpty);
    });

    test('计划与两个原语一致：正常命中时 targets + skipped = 全部课程', () {
      final plan = chaoxingScanPlan(courses, currentTermCode: '261');
      expect(plan.targets.map((c) => c.courseId).toList(), ['1', '3', '4']);
      expect(plan.skipped.map((c) => c.courseId).toList(), ['2', '5']);
      expect(chaoxingScanPlan(courses, currentTermCode: '').targets.length, courses.length);
    });
  });

  group('★ A：扫描状态的文案（未扫到 / 失败 / 非当下学期 三档要分开说）', () {
    final snap = ChaoxingSnapshot(
      courses: [_course('1', '261学期 线性代数(工)')],
      failedCourseKeys: const ['9/9'],
      pendingCourseKeys: const ['8/8'],
      skippedCourseKeys: const ['1/21'],
      fetchedAt: DateTime(2026, 9, 20),
    );

    test('失败 / 未扫到 / 非当下学期 三档文案各不相同', () {
      expect(chaoxingCourseScanNote(snap, '9/9'), '本轮扫描失败，显示的是上次数据');
      expect(chaoxingCourseScanNote(snap, '8/8'), contains('下次进入补扫'));
      expect(chaoxingCourseScanNote(snap, '1/21'), '非当下学期，未扫描（只扫当下学期）');
      expect(chaoxingCourseScanNote(snap, '1/21'), isNot(contains('下次')));
      expect(chaoxingCourseScanNote(snap, '3/3'), '', reason: '正常扫过的课不挂备注');
    });

    test('skipped 是新字段：旧缓存没有这个键 → 空列表、不崩', () {
      final legacy = ChaoxingSnapshot.fromJson({
        'courses': [
          {'courseId': '1', 'classId': '2', 'cpi': '9', 'name': '261学期 线性代数(工)'},
        ],
        'works': const [],
        'notices': const [],
        'failedCourseKeys': const [],
        'pendingCourseKeys': const ['1/2'],
        'throttled': true,
      });
      expect(legacy.skippedCourseKeys, isEmpty);
      expect(legacy.isCourseSkipped('1/2'), isFalse);
      expect(legacy.isCoursePending('1/2'), isTrue);
    });

    test('skipped 进 JSON 往返（落盘再读回不能丢）', () {
      final back = ChaoxingSnapshot.fromJson(snap.toJson());
      expect(back.skippedCourseKeys, ['1/21']);
      expect(back.isCourseSkipped('1/21'), isTrue);
    });
  });

  group('★ B：通知里的作业提醒（用户 2026-09-20 选定的 B 方案）', () {
    ChaoxingNotice notice({
      required String title,
      String courseId = '100000002',
      String id = 'n1',
    }) => ChaoxingNotice(
      id: id,
      title: title,
      content: '正文',
      sender: '某老师',
      courseId: courseId,
      sourceTag: courseId.isEmpty ? '' : 'courseId$courseId',
      sentAt: DateTime(2026, 9, 17, 20, 18),
    );

    test('只认平台自动发的作业通知（`作业:` / `作业：` 开头），不认「作业结束提醒」', () {
      expect(chaoxingNoticeIsWorkPost(notice(title: '作业:《261学期 线性代数（工）》9月20日24:00前提交作业')), isTrue);
      expect(chaoxingNoticeIsWorkPost(notice(title: '作业：《线性代数》第三次作业')), isTrue);
      expect(chaoxingNoticeIsWorkPost(notice(title: '作业结束提醒')), isFalse);
      expect(chaoxingNoticeIsWorkPost(notice(title: '大作业')), isFalse);
      expect(chaoxingNoticeIsWorkPost(notice(title: '261学前测通知及注意事项')), isFalse);
    });

    test('从标题里剥出作业标题（去 `作业:` 前缀与《课程名》）', () {
      expect(
        chaoxingNoticeWorkTitle(notice(title: '作业:《261学期 线性代数（工）》9月20日24:00前提交作业')),
        '9月20日24:00前提交作业',
      );
      expect(
        chaoxingNoticeWorkTitle(notice(title: '作业：《程序设计实践》课程设计评阅表提交')),
        '课程设计评阅表提交',
      );
      expect(chaoxingNoticeWorkTitle(notice(title: '普通通知')), '普通通知');
    });

    ChaoxingSnapshot withWorks(List<ChaoxingWork> works) => ChaoxingSnapshot(
      courses: [_course('100000002', '261学期 线性代数(工)')],
      works: works,
      notices: [
        notice(
          title: '作业:《261学期 线性代数（工）》9月20日24:00前提交作业',
          id: 'dup',
        ),
        notice(title: '作业:《252学期 程序设计实践》课程设计评阅表提交', courseId: '100000006', id: 'gap'),
        notice(title: '作业:没有课程归属的作业通知', courseId: '', id: 'nocourse'),
        notice(title: '作业结束提醒', id: 'ended'),
      ],
      fetchedAt: DateTime(2026, 9, 20),
    );

    test('★ 已扫到的作业不重复显示：标题包含判定', () {
      final hinted = chaoxingNoticeWorkHints(withWorks([
        ChaoxingWork(
          workId: '55739815',
          title: '9月20日24:00前提交作业',
          courseId: '100000002',
          courseName: '261学期 线性代数(工)',
          dueAt: DateTime(2026, 9, 20, 23, 59),
          status: ChaoxingWorkStatus.todo,
        ),
      ]));
      expect(hinted.map((n) => n.id).toList(), ['gap'],
          reason: 'dup 已被作业列表覆盖；ended 不是发布类；nocourse 认不出课程');
    });

    test('作业列表里没有 → 当作提示显示（这就是「补一刀」的价值）', () {
      final hinted = chaoxingNoticeWorkHints(withWorks(const []));
      expect(hinted.map((n) => n.id).toList(), ['dup', 'gap']);
    });

    test('同课有别的作业但标题对不上 → 仍然提示（宁可多提示，不可漏）', () {
      final hinted = chaoxingNoticeWorkHints(withWorks([
        ChaoxingWork(
          workId: 'x',
          title: '第二次作业',
          courseId: '100000002',
          courseName: '261学期 线性代数(工)',
          status: ChaoxingWorkStatus.done,
        ),
      ]));
      expect(hinted.map((n) => n.id), contains('dup'));
    });
  });
}
