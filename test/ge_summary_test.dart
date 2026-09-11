// 分数估计 · 总加权平均汇总（列表页与课程详情页共用口径）单测。
//
// 口径：教务已出成绩全量计入 + 本模块估计（同名由真实成绩计入）+ 学分加权；
// 未填期末 / 学分为 0 不计入但计入 pendingCount；估计侧学分按培养方案优先。

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_curriculum.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_prior_grades.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_summary.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_engine.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_models.dart';

GePriorGrade prior(
  String name,
  double score,
  double credits, {
  String? code,
  String semester = '251',
}) => GePriorGrade(
  courseCode: code ?? name,
  courseName: name,
  score: score,
  credits: credits,
  semester: semester,
);

/// 总评 = 期末分（无分项 + 平时占比 0）。
GeCourse course(
  String name, {
  double? finalScore,
  double credits = 1,
  String code = '',
}) => GeCourse(
  id: 'id-$name',
  name: name,
  courseCode: code,
  dailyPercent: 0,
  credits: credits,
  finalScore: finalScore,
);

void main() {
  group('geSummarize · 教务已出成绩 + 本模块估计', () {
    test('教务全量计入 + 估计分计入 + 未填期末只计数', () {
      final data = geSummarize(
        prior: [prior('高等数学', 90, 4), prior('大学英语', 80, 2)],
        courses: [
          course('数据结构', finalScore: 70, credits: 3),
          course('计算机网络', credits: 2),
        ],
      );
      final s = data.summary;
      expect(s.count, 3);
      expect(s.gradesCount, 2);
      expect(s.estimateCount, 1);
      expect(s.gradesCredits, 6);
      expect(s.estimateCredits, 3);
      expect(s.totalCredits, 9);
      // (90*4 + 80*2 + 70*3) / 9 = 730 / 9
      expect(s.average, closeTo(730 / 9, 1e-9));
      expect(data.pendingCount, 1);
    });

    test('逐课贡献之和 = 加权平均；贡献 = 分数 × 学分 ÷ 总学分', () {
      final data = geSummarize(
        prior: [prior('高等数学', 90, 4)],
        courses: [course('数据结构', finalScore: 70, credits: 3)],
      );
      final s = data.summary;
      var sum = 0.0;
      for (final item in [
        GeWeightItem(name: '高等数学', score: 90, credits: 4),
        GeWeightItem(name: '数据结构', score: 70, credits: 3),
      ]) {
        sum += s.contribution(item);
      }
      expect(
        s.contribution(GeWeightItem(name: '高数', score: 90, credits: 4)),
        closeTo(90 * 4 / 7, 1e-9),
      );
      expect(sum, closeTo(s.average!, 1e-9));
    });

    test('同名课程由教务真实成绩计入，不重复且不算未填期末', () {
      final data = geSummarize(
        prior: [prior('线性代数(工)', 95, 4)],
        // 同名课程未填期末 → 不计入合计，但因教务已出成绩 → 不算 pending。
        courses: [course('线性代数(工)', credits: 1)],
      );
      final s = data.summary;
      expect(s.count, 1);
      expect(s.gradesCount, 1);
      expect(s.estimateCount, 0);
      expect(s.average, closeTo(95, 1e-9));
      expect(data.pendingCount, 0);
    });

    test('学分为 0 的课程不计入且算未计入', () {
      final data = geSummarize(
        prior: const [],
        courses: [course('体育保健学', finalScore: 88, credits: 0)],
      );
      expect(data.summary.isEmpty, isTrue);
      expect(data.summary.average, isNull);
      expect(data.pendingCount, 1);
    });

    test('全部未填期末 → 空汇总，pendingCount 为课程数', () {
      final data = geSummarize(
        prior: const [],
        courses: [course('A'), course('B'), course('C')],
      );
      expect(data.summary.isEmpty, isTrue);
      expect(data.pendingCount, 3);
    });
  });

  group('geSummarize · 学分按培养方案优先', () {
    test('方案命中 → 用方案学分（课程自身学分为 1 也不影响）', () {
      final index = GeCurriculumIndex.fromCourses(
        majorName: '计算机科学与技术',
        courses: const [(code: 'C1', name: '数据结构与算法', credits: 4.0)],
      );
      final data = geSummarize(
        prior: [prior('高等数学', 90, 4), prior('大学英语', 80, 2)],
        courses: [course('数据结构与算法', finalScore: 70, credits: 1, code: 'C1')],
        index: index,
      );
      final s = data.summary;
      // (90*4 + 80*2 + 70*4) / 10 = 800 / 10
      expect(s.totalCredits, 10);
      expect(s.average, closeTo(80, 1e-9));
    });

    test('方案未命中 → 回退课程自身学分', () {
      final index = GeCurriculumIndex.fromCourses(
        majorName: '计算机科学与技术',
        courses: const [(code: 'C1', name: '数据结构与算法', credits: 4.0)],
      );
      final data = geSummarize(
        prior: const [],
        courses: [course('体育保健学（MOOC）', finalScore: 90, credits: 2)],
        index: index,
      );
      expect(data.summary.totalCredits, 2);
      expect(data.summary.average, closeTo(90, 1e-9));
    });

    test('方案里学分为 0 的条目被忽略 → 回退课程自身学分', () {
      final index = GeCurriculumIndex.fromCourses(
        majorName: '计算机科学与技术',
        courses: const [(code: 'C9', name: '讲座', credits: 0.0)],
      );
      final data = geSummarize(
        prior: const [],
        courses: [course('讲座', finalScore: 90, credits: 1, code: 'C9')],
        index: index,
      );
      expect(index.isEmpty, isTrue);
      expect(data.summary.totalCredits, 1);
      expect(data.summary.average, closeTo(90, 1e-9));
      expect(data.pendingCount, 0);
    });
  });
}
