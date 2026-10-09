import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_exclusions.dart';

/// 「实践类课程不计入加权」的判据（2026-10-08 从「手写四个课名」改成
/// **由本专业实践环节表推导**）。
///
/// 用户原话：「还有一个联动的部分，那就是『实践环节』一般不计入加权成绩，详见各材料」。
/// 材料出处 = `assets/rules/text/r05a.md` 第二十四条注 4：
/// 「实践类课程（如毕业论文、毕业实习等），不计入课程加权平均成绩。」
/// （`r08a` / `r09a` / `r10a` / `r23a` 同款条款。）
void main() {
  const practice = PracticeCurriculum(
    year: 2025,
    collegeName: '示例学院',
    majorName: '示例专业',
    stages: [
      PracticeStage(index: 1, code: '1305002302', name: '军事训练', credit: 2),
      PracticeStage(index: 2, code: '1302600064', name: '创新创业实践活动', credit: 4),
      PracticeStage(index: 3, code: '1314300014', name: '毕业实习', credit: 4),
      PracticeStage(index: 4, code: '1314300058', name: '毕业设计', credit: 8),
    ],
  );

  group('判据来源 = 实践环节表', () {
    test('表里的环节按**代码**命中（成绩表课程名被改过也认得出）', () {
      final f = PracticeCourseFilter.fromPractice(practice);
      expect(f.excludes(code: '1314300014', name: '随便什么名字'), isTrue);
      expect(f.excludes(code: '1305002302', name: '军训'), isTrue);
    });

    test('表里的环节按**名称**也命中', () {
      final f = PracticeCourseFilter.fromPractice(practice);
      expect(f.excludes(name: '毕业实习'), isTrue);
      expect(f.excludes(name: '毕业设计'), isTrue);
    });

    test('★ 历史那份四个课名的名单并集保留（表里没有「毕业论文」也照样排除）', () {
      final f = PracticeCourseFilter.fromPractice(practice);
      expect(f.excludes(name: '毕业论文'), isTrue, reason: '历史名单不许丢');
      expect(f.names, containsAll(kExcludedGradeCourses));
    });

    test('理论课不受影响（别把「大学英语I」也算成实践类）', () {
      final f = PracticeCourseFilter.fromPractice(practice);
      expect(f.excludes(code: '1004600232', name: '大学英语I'), isFalse);
      expect(f.excludes(code: '1004701034', name: '高等数学I'), isFalse);
      expect(f.excludes(code: '1014300154', name: '程序设计基础'), isFalse);
    });

    test('代码优先、名称兜底；两者都空时不算命中', () {
      final f = PracticeCourseFilter.fromPractice(practice);
      expect(f.excludes(), isFalse);
      expect(f.excludes(code: '', name: ''), isFalse);
    });
  });

  group('降级：表拿不到时行为与从前**逐字不变**', () {
    test('null → 用历史名单', () {
      final f = PracticeCourseFilter.fromPractice(null);
      expect(f, same(PracticeCourseFilter.fallback));
      expect(f.codes, isEmpty);
      for (final n in kExcludedGradeCourses) {
        expect(f.excludes(name: n), isTrue, reason: '$n 从前就是排除的');
      }
      expect(f.excludes(name: '毕业实习'), isFalse, reason: '没表时认不出它');
    });

    test('空表（有表但一条都没有）→ 也退回历史名单', () {
      const empty = PracticeCurriculum(
        year: 2025,
        collegeName: 'X',
        majorName: 'Y',
        stages: [],
      );
      final f = PracticeCourseFilter.fromPractice(empty);
      expect(f.codes, isEmpty);
      expect(f.names, kExcludedGradeCourses);
    });

    test('默认构造 = 历史行为', () {
      const f = PracticeCourseFilter();
      expect(f.names, kExcludedGradeCourses);
      expect(f.codes, isEmpty);
    });
  });

  group('excludesName：给手上没有课程代码的老调用方', () {
    test('只看名称', () {
      final f = PracticeCourseFilter.fromPractice(practice);
      expect(f.excludesName('毕业实习'), isTrue);
      expect(f.excludesName('  军事训练  '), isTrue, reason: '要去首尾空白');
      expect(f.excludesName('大学英语I'), isFalse);
    });
  });
}
