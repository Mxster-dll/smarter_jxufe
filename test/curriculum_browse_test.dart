// 培养方案「浏览态」纯逻辑守卫（2026-10-09 立）。
//
// 页面（`curriculum_screen.dart`）只负责画，分组 / 搜索 / 快筛 / 汇总全在
// `domain/curriculum_browse.dart` —— 这里把那些判据钉住：
// - 三种分组形态（按分类 / 按开课学期 / 平铺）的顺序与小计；
// - 开课学期：**认不出的排最后**（不许冒充第一学期）、侧表缺行时一律「未排定」；
// - 搜索命中课名 / 代码 / 类别；快筛「选修」= 非必修；
// - 实践环节的快筛语义（整张表都是必修 → 「选修 / 主干」把它筛空是实话）。
//
// 数据全是**合成**的（形状照真实教学计划表缩样）。

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/assessment_method.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_nature.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_requirement.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/credit_hour.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_browse.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_terms.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';

Course _course({
  required String code,
  required String name,
  required double credit,
  required String main,
  required String sub,
  CourseRequirement requirement = CourseRequirement.compulsory,
  CourseImportance importance = CourseImportance.general,
}) => Course(
  code: code,
  name: name,
  credit: credit,
  creditHour: const CreditHour(
    total: 32,
    lecture: 32,
    lab: 0,
    practice: 0,
    other: 0,
    weekly: 2,
  ),
  mainCategory: main,
  subCategory: sub,
  tertiaryCategory: null,
  requirement: requirement,
  nature: CourseNature.theory,
  importance: importance,
  assessmentMethod: AssessmentMethod.exam,
  identification: '',
);

/// 形状照真实表：公共课 → 专业教育课 → 通识教育课，必修与选修混着。
final _courses = <Course>[
  _course(
    code: '1000000001',
    name: '高等数学A',
    credit: 4,
    main: '2024公共课',
    sub: '公共数学课',
    importance: CourseImportance.core,
  ),
  _course(
    code: '1000000002',
    name: '大学英语I',
    credit: 2,
    main: '2024公共课',
    sub: '公共外语课',
  ),
  _course(
    code: '1000000011',
    name: '六级英语专题',
    credit: 2,
    main: '2024公共课',
    sub: '公共外语课',
    requirement: CourseRequirement.elective,
  ),
  _course(
    code: '1000000021',
    name: '程序设计基础',
    credit: 4,
    main: '2024专业教育课',
    sub: '学科基础课',
    importance: CourseImportance.core,
  ),
  _course(
    code: '1000000031',
    name: 'Linux操作系统',
    credit: 2,
    main: '2024专业教育课',
    sub: '专业方向课',
    requirement: CourseRequirement.elective,
  ),
  _course(
    code: '1000000041',
    name: '限选专题',
    credit: 1.5,
    main: '2024专业教育课',
    sub: '专业限选课',
    requirement: CourseRequirement.restricted,
  ),
  _course(
    code: '1000000051',
    name: '写作与沟通I',
    credit: 1.5,
    main: '2024通识教育课',
    sub: '哲学、思维与语言',
  ),
];

/// 与 [_courses] 同序的开课学期（最后两门**没排定**）。
const _semesters = [
  '2025-2026学年第一学期',
  '2025-2026学年第一学期',
  '2025-2026学年第二学期',
  '2026-2027学年第一学期',
  '2026-2027学年第一学期',
  '',
  '',
];

void main() {
  group('按分类聚合', () {
    test('★ 大类 → 二级分类：都按首次出现顺序，组内小计正确', () {
      final result = browseCurriculum(courses: _courses);
      expect(result.sections.map((s) => s.title), [
        '2024公共课',
        '2024专业教育课',
        '2024通识教育课',
      ]);
      final public = result.sections.first;
      expect(public.groups.map((g) => g.title), ['公共数学课', '公共外语课']);
      expect(public.groups.first.count, 1);
      expect(public.groups.first.credits, 4);
      // 公共外语课：必修 2 + 选修 2
      expect(public.groups.last.count, 2);
      expect(public.groups.last.credits, 4);
      expect(public.count, 3);
      expect(public.credits, 8);
    });

    test('组内保持教务原顺序（不排序、不打乱）', () {
      final result = browseCurriculum(courses: _courses);
      final major = result.sections[1];
      expect(major.groups.first.items.map((i) => i.course.name), ['程序设计基础']);
      expect(
        major.groups.last.items.single.index,
        6,
        reason: '行号 = 教务表原行号（1 起）',
      );
    });

    test('大类 / 二级分类为空 → 归到「未分类」，不丢课', () {
      final result = browseCurriculum(
        courses: [
          _course(code: '1', name: '没分类的课', credit: 1, main: '', sub: ''),
        ],
      );
      expect(result.sections.single.title, '未分类');
      expect(result.sections.single.groups.single.title, '未分类');
      expect(result.totalCount, 1);
    });
  });

  group('按开课学期聚合', () {
    test('★ 学期按学年学期先后排，「未排定」排最后（不当成第一学期）', () {
      final result = browseCurriculum(
        courses: _courses,
        semesters: _semesters,
        mode: CurriculumGroupMode.term,
      );
      expect(result.sections.map((s) => s.title), [
        '2025-2026 学年第一学期',
        '2025-2026 学年第二学期',
        '2026-2027 学年第一学期',
        kCurriculumTermUnassigned,
      ]);
      expect(result.sections.first.code, '251', reason: '节标题旁边给学期短码');
      expect(result.sections.last.code, isNull);
      expect(result.sections.last.count, 2);
    });

    test('每个学期里再按课程大类分一层', () {
      final result = browseCurriculum(
        courses: _courses,
        semesters: _semesters,
        mode: CurriculumGroupMode.term,
      );
      final first = result.sections.first;
      expect(first.groups.map((g) => g.title), ['2024公共课']);
      expect(first.count, 2);
      expect(first.credits, 6);
    });

    test('★ 侧表缺行 / 长度对不上：一律「未排定」，不许错位', () {
      final result = browseCurriculum(
        courses: _courses,
        semesters: const ['2025-2026学年第一学期'], // 只有一行
        mode: CurriculumGroupMode.term,
      );
      final first = result.sections.first;
      expect(first.title, '2025-2026 学年第一学期');
      expect(first.count, 1);
      expect(result.sections.last.title, kCurriculumTermUnassigned);
      expect(result.sections.last.count, _courses.length - 1);
    });

    test('完全没给侧表 → 全部归「未排定」（页面另有提示文案）', () {
      final result = browseCurriculum(
        courses: _courses,
        mode: CurriculumGroupMode.term,
      );
      expect(result.sections.length, 1);
      expect(result.sections.single.title, kCurriculumTermUnassigned);
      expect(result.sections.single.count, _courses.length);
    });
  });

  group('平铺', () {
    test('只有一节「全部课程」，一组、原顺序', () {
      final result = browseCurriculum(
        courses: _courses,
        mode: CurriculumGroupMode.flat,
      );
      expect(result.sections.single.title, '全部课程');
      expect(result.sections.single.groups.single.title, isEmpty);
      expect(
        result.sections.single.groups.single.items.map((i) => i.course.name),
        _courses.map((c) => c.name),
      );
    });
  });

  group('搜索', () {
    test('命中课名 / 课程代码 / 大类 / 二级分类', () {
      for (final (query, expected) in [
        ('linux', 1),
        ('LINUX', 1), // 大小写无关
        ('1000000002', 1),
        ('专业教育', 3), // 大类
        ('公共外语', 2), // 二级分类
        ('  英语  ', 2), // 两端空白先 trim（「大学英语I」+「六级英语专题」）
      ]) {
        final result = browseCurriculum(courses: _courses, query: query);
        expect(result.matchedCount, expected, reason: '搜「$query」');
      }
    });

    test('搜不到时命中 0，但总数与合计照旧（页面据此写「共 N 门」）', () {
      final result = browseCurriculum(courses: _courses, query: '不存在的课');
      expect(result.isEmpty, isTrue);
      expect(result.matchedCount, 0);
      expect(result.totalCount, _courses.length);
      expect(result.totalCredits, 17);
      expect(result.filtered, isTrue);
    });

    test('空搜索 = 不筛（filtered 为 false）', () {
      final result = browseCurriculum(courses: _courses, query: '   ');
      expect(result.filtered, isFalse);
      expect(result.matchedCount, result.totalCount);
    });
  });

  group('快筛', () {
    test('必修 / 选修（= 非必修，含限选）/ 主干课程', () {
      expect(
        browseCurriculum(
          courses: _courses,
          filter: CurriculumQuickFilter.compulsory,
        ).matchedCount,
        4,
      );
      expect(
        browseCurriculum(
          courses: _courses,
          filter: CurriculumQuickFilter.elective,
        ).matchedCount,
        3,
        reason: '选修（六级英语专题、Linux）+ 限选（限选专题）都算选修侧',
      );
      expect(
        browseCurriculum(
          courses: _courses,
          filter: CurriculumQuickFilter.core,
        ).matchedCount,
        2,
      );
    });

    test('筛选后合计只算命中的（页面写「命中 N 门 · M 学分」）', () {
      final result = browseCurriculum(
        courses: _courses,
        filter: CurriculumQuickFilter.compulsory,
      );
      expect(result.matchedCredits, 11.5);
      expect(result.totalCredits, 17);
      expect(result.filtered, isTrue);
    });

    test('筛选与搜索叠加（取交集）', () {
      final result = browseCurriculum(
        courses: _courses,
        query: '英语',
        filter: CurriculumQuickFilter.compulsory,
      );
      expect(result.matchedCount, 1);
      expect(result.sections.single.groups.last.items.single.course.name, '大学英语I');
    });
  });

  group('总览汇总', () {
    test('门数 / 学分 / 必修与非必修 / 主干 / 大类占比', () {
      final summary = summarizeCurriculum(_courses);
      expect(summary.totalCount, 7);
      expect(summary.totalCredits, 17);
      expect(summary.compulsoryCount, 4);
      expect(summary.compulsoryCredits, 11.5);
      expect(summary.otherCount, 3);
      expect(summary.otherCredits, 5.5);
      expect(summary.coreCount, 2);
      expect(summary.categoryShares.map((s) => s.label), [
        '2024公共课',
        '2024专业教育课',
        '2024通识教育课',
      ]);
      expect(summary.categoryShares.map((s) => s.credits), [8, 7.5, 1.5]);
    });

    test('空方案：全 0，不抛（页面画「没有课程条目」）', () {
      final summary = summarizeCurriculum(const []);
      expect(summary.totalCount, 0);
      expect(summary.totalCredits, 0);
      expect(summary.categoryShares, isEmpty);
      expect(browseCurriculum(courses: const []).isEmpty, isTrue);
    });
  });

  group('修读性质短标签', () {
    test('只削结尾的「课」，其余性质原样', () {
      expect(curriculumRequirementShort(CourseRequirement.compulsory), '必修');
      expect(curriculumRequirementShort(CourseRequirement.elective), '选修');
      expect(curriculumRequirementShort(CourseRequirement.restricted), '限选');
      expect(curriculumRequirementShort(CourseRequirement.free), '任选');
      expect(curriculumRequirementShort(CourseRequirement.excellence), '卓越型');
      expect(curriculumRequirementShort(CourseRequirement.unknown), '未知');
    });
  });

  group('实践环节（培养方案第二张表）', () {
    const stages = [
      PracticeStage(
        index: 1,
        code: '1305002302',
        name: '军事训练',
        credit: 2,
        category: '军训',
        assessment: '考查',
        weeks: 2,
        semester: '2025-2026学年第一学期',
      ),
      PracticeStage(
        index: 2,
        code: '1302600064',
        name: '创新创业实践活动',
        credit: 4,
        category: '科研创新实践',
        assessment: '考查',
        weeks: 8,
        semester: '2028-2029学年第二学期',
      ),
      PracticeStage(
        index: 3,
        code: '1314300014',
        name: '毕业实习',
        credit: 4,
        category: '实习实训',
        assessment: '考查',
        weeks: 4,
      ),
    ];

    test('按环节类别聚（顺序照表）', () {
      final result = browsePractice(stages: stages);
      expect(result.groups.map((g) => g.title), ['军训', '科研创新实践', '实习实训']);
      expect(result.totalCredits, 10);
      expect(result.groups.first.credits, 2);
    });

    test('按开课学期聚：先后有序，没排定的排最后', () {
      final result = browsePractice(
        stages: stages,
        mode: CurriculumGroupMode.term,
      );
      expect(result.groups.map((g) => g.title), [
        '2025-2026 学年第一学期',
        '2028-2029 学年第二学期',
        kCurriculumTermUnassigned,
      ]);
    });

    test('平铺：一组、原顺序', () {
      final result = browsePractice(
        stages: stages,
        mode: CurriculumGroupMode.flat,
      );
      expect(result.groups.single.title, isEmpty);
      expect(result.groups.single.stages.map((s) => s.name), [
        '军事训练',
        '创新创业实践活动',
        '毕业实习',
      ]);
    });

    test('搜索命中环节名 / 类别 / 学期', () {
      expect(browsePractice(stages: stages, query: '实习').matchedCount, 1);
      expect(browsePractice(stages: stages, query: '科研').matchedCount, 1);
      expect(browsePractice(stages: stages, query: '2028').matchedCount, 1);
    });

    test('★ 快筛语义：必修保留全部；「选修」「主干」把它筛空（都是实话）', () {
      expect(
        browsePractice(
          stages: stages,
          filter: CurriculumQuickFilter.compulsory,
        ).matchedCount,
        3,
      );
      for (final filter in [
        CurriculumQuickFilter.elective,
        CurriculumQuickFilter.core,
      ]) {
        final result = browsePractice(stages: stages, filter: filter);
        expect(result.isEmpty, isTrue, reason: '$filter');
        expect(result.totalCount, 3, reason: '总数不受影响，页面照写「共 3 项」');
      }
    });

    test('空表：不抛、不编（页面画「没有条目」那一句）', () {
      final result = browsePractice(stages: const []);
      expect(result.isEmpty, isTrue);
      expect(result.groups, isEmpty);
      expect(result.totalCount, 0);
    });
  });

  group('两张表的重叠统计（脚注用）', () {
    test('按环节代码 / 名称对上理论课程', () {
      final courses = [
        ..._courses,
        _course(
          code: '1300000001',
          name: '劳动教育',
          credit: 1,
          main: '2024实践教育课',
          sub: '劳动教育',
        ),
      ];
      const practice = PracticeCurriculum(
        year: 2025,
        collegeName: '计算机与人工智能学院',
        majorName: '计算机科学与技术',
        stages: [
          PracticeStage(
            index: 1,
            code: '1300000001',
            name: '劳动教育',
            credit: 1,
            category: '军训',
          ),
          PracticeStage(
            index: 2,
            code: '1302600064',
            name: '创新创业实践活动',
            credit: 4,
            category: '科研创新实践',
          ),
        ],
      );
      expect(
        curriculumPracticeOverlap(courses: courses, practice: practice),
        1,
      );
      expect(
        curriculumPracticeOverlap(courses: _courses, practice: practice),
        0,
      );
    });
  });
}
