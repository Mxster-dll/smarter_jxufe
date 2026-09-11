// 分数估计 · 培养方案学分索引单测（纯逻辑，无 IO）。
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/score_estimate/data/ge_curriculum.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_models.dart';

GeCourse _course({
  String id = 'c1',
  String name = '计算机网络',
  String courseCode = '',
  double credits = 1,
}) => GeCourse(id: id, name: name, courseCode: courseCode, credits: credits);

void main() {
  group('GeCurriculumIndex 匹配', () {
    final index = GeCurriculumIndex.fromCourses(
      majorName: '计算机科学与技术',
      courses: const [
        (code: '1014300174', name: '计算机网络', credits: 4),
        (code: '1014300314', name: '数据结构与算法', credits: 4),
        (code: '1012100360', name: '形势与政策III', credits: 0.5),
        (code: '1014300422', name: 'Linux操作系统', credits: 2),
        (code: '9999999999', name: '同名不同码的课', credits: 3),
        (code: '', name: '无代码课程', credits: 2),
        (code: '8888888888', name: '零学分课程', credits: 0),
      ],
    );

    test('空索引 / 非空索引判定', () {
      expect(const GeCurriculumIndex.empty().isEmpty, isTrue);
      expect(const GeCurriculumIndex.empty().creditsOf(name: 'X'), isNull);
      expect(index.isEmpty, isFalse);
      expect(index.majorName, '计算机科学与技术');
      expect(index.codeCount, 5); // 含 1 门无代码课程；零学分课程被忽略
      expect(index.nameCount, 6);
    });

    test('按课程名精确匹配（忽略空白与大小写）', () {
      expect(index.creditsOf(name: '计算机网络'), 4);
      expect(index.creditsOf(name: ' 计算机网络 '), 4);
      expect(index.creditsOf(name: 'linux操作系统'), 2);
      expect(index.creditsOf(name: '形势与政策III'), 0.5);
    });

    test('课程代码优先于课程名', () {
      // 代码指向另一门课（4 学分）时，不应被同名课程的 3 学分覆盖。
      final clash = GeCurriculumIndex.fromCourses(
        majorName: 'X',
        courses: const [
          (code: 'A1', name: '程序设计', credits: 2),
          (code: 'A2', name: '程序设计', credits: 5),
        ],
      );
      expect(clash.creditsOf(code: 'A2', name: '程序设计'), 5);
      expect(clash.creditsOf(code: 'A1', name: '程序设计'), 2);
      // 代码未命中 → 回落课程名（后写入者胜，此处为 A2 的 5）。
      expect(clash.creditsOf(code: 'NOPE', name: '程序设计'), 5);
      expect(clash.creditsOf(code: 'A2', name: '别的课名'), 5);
    });

    test('未匹配 / 空名 / 零学分 → null', () {
      expect(index.creditsOf(name: '体育保健学（MOOC）'), isNull);
      expect(index.creditsOf(name: '   '), isNull);
      expect(index.creditsOf(code: '', name: ''), isNull);
      expect(index.creditsOf(code: '8888888888', name: '零学分课程'), isNull);
    });
  });

  group('geEffectiveCredits 有效学分', () {
    final index = GeCurriculumIndex.fromCourses(
      majorName: '计算机科学与技术',
      courses: const [(code: '1014300174', name: '计算机网络', credits: 4)],
    );

    test('培养方案命中 → 用方案学分并标记来源', () {
      final eff = geEffectiveCredits(index, _course(credits: 1));
      expect(eff.credits, 4);
      expect(eff.fromCurriculum, isTrue);
    });

    test('培养方案命中（按代码）→ 用方案学分', () {
      final eff = geEffectiveCredits(
        index,
        _course(name: '计网（课表简称）', courseCode: '1014300174', credits: 1),
      );
      expect(eff.credits, 4);
      expect(eff.fromCurriculum, isTrue);
    });

    test('培养方案未命中 → 回退课程自身学分', () {
      final eff = geEffectiveCredits(
        index,
        _course(name: '体育保健学（MOOC）', credits: 1.5),
      );
      expect(eff.credits, 1.5);
      expect(eff.fromCurriculum, isFalse);
    });

    test('空索引 → 回退课程自身学分', () {
      final eff = geEffectiveCredits(
        const GeCurriculumIndex.empty(),
        _course(credits: 3),
      );
      expect(eff.credits, 3);
      expect(eff.fromCurriculum, isFalse);
    });
  });

  group('GeCourse.courseCode 序列化', () {
    test('往返保留课程代码', () {
      final c = _course(courseCode: '1014300174');
      final back = GeCourse.fromJson(c.toJson());
      expect(back.courseCode, '1014300174');
      expect(back.credits, 1);
    });

    test('旧数据（无 courseCode / credits）→ 空代码 + 1 学分', () {
      final back = GeCourse.fromJson({
        'id': 'x',
        'name': '英语视听说',
        'dailyPercent': 50,
        'parts': const [],
        'finalScore': 60,
        'note': '',
        'createdAt': 1,
      });
      expect(back.courseCode, '');
      expect(back.credits, 1);
      expect(back.dailyPercent, 50);
    });

    test('copyWith 可写入课程代码与学分', () {
      final c = _course().copyWith(courseCode: 'A1', credits: 4);
      expect(c.courseCode, 'A1');
      expect(c.credits, 4);
      expect(c.name, '计算机网络');
    });
  });
}
