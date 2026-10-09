import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/course/data/models/assessment_method.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_nature.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_requirement.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/credit_hour.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/credit_progress.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/general_education_catalog.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/graduation_requirement.dart';

// ───────────────────────── fixtures ─────────────────────────

Course _course(
  String code,
  String name,
  double credit,
  String main,
  String sub,
  CourseRequirement requirement,
) => Course(
  code: code,
  name: name,
  credit: credit,
  creditHour: const CreditHour(total: 32, lecture: 32, weekly: 2),
  mainCategory: main,
  subCategory: sub,
  tertiaryCategory: null,
  requirement: requirement,
  nature: CourseNature.theory,
  importance: CourseImportance.general,
  assessmentMethod: AssessmentMethod.exam,
  identification: '',
);

/// 培养方案形状照真实数据（2025 计算机科学与技术）缩样：
/// 必修里既有公共外语课，也有一门**性质为必修的通识课**（写作与沟通I）——
/// 后者正是「必修课不能顶通识选修」那条口径的试金石。
final _curriculum = Curriculum(
  year: 2025,
  collegeName: '计算机与人工智能学院',
  majorName: '计算机科学与技术',
  courses: [
    // ── 必修 ──
    _course('1004600232', '大学英语I', 2, '2024公共课', '公共外语课', CourseRequirement.compulsory),
    _course('1004600282', '大学英语II', 2, '2024公共课', '公共外语课', CourseRequirement.compulsory),
    _course('1004701034', '高等数学I', 4, '2024公共课', '公共数学课', CourseRequirement.compulsory),
    _course('1014300154', '程序设计基础', 4, '2024专业教育课', '学科基础课', CourseRequirement.compulsory),
    _course('1004907141', '写作与沟通I', 1.5, '2024通识教育课', '哲学、思维与语言', CourseRequirement.compulsory),
    // ── 选修 ──
    _course('1004601702', '六级英语专题', 2, '2024公共课', '公共外语课', CourseRequirement.elective),
    _course('1004606282', '考研英语专题', 2, '2024公共课', '公共外语课', CourseRequirement.elective),
    _course('1004501303', '管理学原理', 3, '2024专业教育课', '学科开放课', CourseRequirement.elective),
    _course('1004201913', '金融学', 3, '2024专业教育课', '学科开放课', CourseRequirement.elective),
    _course('1014300422', 'Linux操作系统', 2, '2024专业教育课', '专业方向课', CourseRequirement.elective),
    _course('1004703083', '数学建模', 3, '2024专业教育课', '专业方向课', CourseRequirement.elective),
    _course('1004701363', '计量经济学', 3, '2024专业教育课', '专业方向课', CourseRequirement.elective),
    // 未在教务要求项里的类别（专业限选课）——用来验「归类了但没要求项」的理由文案
    _course('1014300999', '限选专题', 2, '2024专业教育课', '专业限选课', CourseRequirement.elective),
    // ── 通识选修占位课 ──
    _course('1002302502', '哲学、思维与语言模块', 2, '2024通识教育课', '哲学、思维与语言', CourseRequirement.elective),
    _course('1002302532', '美育模块', 2, '2024公共课', '美育', CourseRequirement.elective),
  ],
);

/// 教务「毕业学分要求」表 —— 7 项 + 合计（2026-09 实测原文，逐字照抄）。
const _requirements = <GraduationRequirement>[
  GraduationRequirement(index: 1, item: '2024公共外语选修课', credit: 2),
  GraduationRequirement(index: 2, item: '2024美育选修2学分', credit: 2),
  GraduationRequirement(index: 3, item: '2024科学、技术与方法选修2学分', credit: 2),
  GraduationRequirement(index: 4, item: '2024历史、政治与社会选修2学分', credit: 2),
  GraduationRequirement(index: 5, item: '2024哲学、思维与语言选修2学分', credit: 2),
  GraduationRequirement(index: 6, item: '2024学科开放选修课', credit: 3),
  GraduationRequirement(index: 7, item: '2024专业方向选修课', credit: 15),
  GraduationRequirement(index: 8, item: '合计', credit: 28, isTotal: true),
];

/// 一张小的通识课程库（形状照真实 asset：年级表 + 各年级表）。
GeneralEducationCatalog _catalog() => const GeneralEducationCatalog(
  revision: 'test',
  sourceName: 'test',
  sheets: [
    GeneralEducationSheet(
      title: '校内库（2024-2025级）',
      cohortFrom: 2024,
      cohortTo: 2025,
      courses: [
        GeneralEducationCourse(
          code: '1004809771',
          name: '工艺美术简史',
          credit: 1.5,
          module: GeneralEducationModule.aesthetic,
          sheetTitle: '校内库（2024-2025级）',
        ),
        GeneralEducationCourse(
          code: '1004909711',
          name: '中华优秀传统文化概论',
          credit: 1.5,
          module: GeneralEducationModule.historyPoliticsSociety,
          sheetTitle: '校内库（2024-2025级）',
          oldCodes: ['1004908961'],
        ),
        GeneralEducationCourse(
          // 只在这张表里、且没有模块标签 —— 真实 asset 里 2021-2023 表头 89 门就是这样
          code: '1004607181',
          name: '战后日本经济与社会',
          credit: 1,
          sheetTitle: '校内库（2024-2025级）',
        ),
        GeneralEducationCourse(
          code: '1006001211',
          name: '地产与财富',
          credit: 1.5,
          module: GeneralEducationModule.developmentGuidance,
          sheetTitle: '校内库（2024-2025级）',
        ),
      ],
    ),
    GeneralEducationSheet(
      title: '外校网课（各年级）',
      allCohorts: true,
      courses: [
        GeneralEducationCourse(
          code: '1602302940',
          name: '习近平外交思想(尔雅网络课程)',
          credit: 0.5,
          module: GeneralEducationModule.historyPoliticsSociety,
          sheetTitle: '外校网课（各年级）',
        ),
        GeneralEducationCourse(
          code: '1602303171',
          name: '《汉书》导读(尔雅网络课程)',
          credit: 1,
          module: GeneralEducationModule.historyPoliticsSociety,
          sheetTitle: '外校网课（各年级）',
          oldCodes: ['1602300052'],
        ),
      ],
    ),
  ],
);

/// 培养方案**实践环节**表（形状照真实抓包；军事训练只在这张表里）。
const _practice = PracticeCurriculum(
  year: 2025,
  collegeName: '计算机与人工智能学院',
  majorName: '计算机科学与技术',
  stages: [
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
    PracticeStage(
      index: 4,
      code: '1314300058',
      name: '毕业设计',
      credit: 8,
      category: '论文设计',
      assessment: '考查',
      weeks: 8,
    ),
  ],
);

TakenCourse _taken(
  String code,
  String name,
  double credit,
  double earned, {
  String semester = '251',
  double? score,
}) => TakenCourse(
  code: code,
  name: name,
  credit: credit,
  earned: earned,
  semester: semester,
  score: score,
);

GraduationCreditProgress _build({
  List<TakenCourse> taken = const [],
  List<TakenCourse> inProgress = const [],
  Curriculum? curriculum,
  PracticeCurriculum? practice,
  bool withCurriculum = true,
  bool withPractice = true,
}) => buildGraduationCreditProgress(
  requirements: _requirements,
  taken: taken,
  inProgress: inProgress,
  curriculum: withCurriculum ? (curriculum ?? _curriculum) : null,
  practice: withPractice ? (practice ?? _practice) : null,
  catalog: _catalog(),
  cohort: 2025,
);

CreditProgressItem _item(GraduationCreditProgress p, String keyword) =>
    p.electives.firstWhere((e) => e.title.contains(keyword));

void main() {
  group('要求项 → 口径 的解析', () {
    test('7 项真实要求项全部识别得出规则', () {
      for (final r in _requirements) {
        if (r.isTotal) continue;
        expect(
          resolveElectiveRule(r.item),
          isNotNull,
          reason: '「${r.item}」没被识别',
        );
      }
    });

    test('三类专业选修落到培养方案二级分类，四项通识落到通识模块', () {
      expect(resolveElectiveRule('2024公共外语选修课')?.subCategory, '公共外语课');
      expect(resolveElectiveRule('2024学科开放选修课')?.subCategory, '学科开放课');
      expect(resolveElectiveRule('2024专业方向选修课')?.subCategory, '专业方向课');
      expect(
        resolveElectiveRule('2024美育选修2学分')?.module,
        GeneralEducationModule.aesthetic,
      );
      expect(
        resolveElectiveRule('2024科学、技术与方法选修2学分')?.module,
        GeneralEducationModule.scienceTechnologyMethod,
      );
    });

    test('认不出的要求项返回 null（不猜），页面上只显示要求学分', () {
      expect(resolveElectiveRule('2024创新创业实践'), isNull);
      expect(resolveElectiveRule(''), isNull);
      final p = _build();
      // 造一条认不出的要求项
      final p2 = buildGraduationCreditProgress(
        requirements: const [
          GraduationRequirement(index: 1, item: '2024神秘选修课', credit: 6),
        ],
        taken: const [],
        curriculum: _curriculum,
        catalog: _catalog(),
        cohort: 2025,
      );
      expect(p.electives, hasLength(7));
      expect(p2.electives.single.recognized, isFalse);
      expect(p2.electives.single.required, 6);
      expect(p2.electives.single.earned, 0);
      expect(p2.electives.single.rule, contains('未识别'));
    });
  });

  group('必修进度', () {
    test('分母 = 培养方案里全部必修课（未修的也进分母）', () {
      final p = _build();
      expect(p.compulsory.available, isTrue);
      expect(p.compulsory.totalCount, 5);
      expect(p.compulsory.required, 2 + 2 + 4 + 4 + 1.5);
      expect(p.compulsory.earned, 0);
      expect(p.compulsory.remaining, 13.5);
      expect(p.compulsory.pendingCourses, hasLength(5));
    });

    test('已修的必修课计入，未修的不计', () {
      final p = _build(
        taken: [
          _taken('1004600232', '大学英语I', 2, 2),
          _taken('1004701034', '高等数学I', 4, 4),
        ],
      );
      expect(p.compulsory.earned, 6);
      expect(p.compulsory.remaining, 7.5);
      expect(p.compulsory.doneCount, 2);
      expect(p.compulsory.pendingCourses.map((c) => c.name), [
        '大学英语II',
        '程序设计基础',
        '写作与沟通I',
      ]);
    });

    test('成绩缺课程代码时按课程名兜底匹配', () {
      final p = _build(taken: [_taken('', '高等数学I', 4, 4)]);
      expect(p.compulsory.earned, 4);
    });

    test('挂科（获得学分 0）不计入，且这门课仍留在待修清单里', () {
      final p = _build(taken: [_taken('1004701034', '高等数学I', 4, 0)]);
      expect(p.compulsory.earned, 0);
      expect(p.compulsory.pendingCourses.map((c) => c.name), contains('高等数学I'));
    });

    test('重修：同码两条只算一次，取拿到学分的那次', () {
      final p = _build(
        taken: [
          _taken('1004701034', '高等数学I', 4, 0, semester: '251'),
          _taken('1004701034', '高等数学I', 4, 4, semester: '252'),
        ],
      );
      expect(p.compulsory.earned, 4, reason: '不许把两次的学分加起来');
      final state = p.compulsory.courses.firstWhere((c) => c.name == '高等数学I');
      expect(state.done, isTrue);
      expect(state.semester, '252');
    });

    test('培养方案拿不到 → available=false，不假装「已修满」', () {
      final p = _build(withCurriculum: false);
      expect(p.compulsory.available, isFalse);
      expect(p.compulsory.satisfied, isFalse);
      expect(p.compulsory.remaining, 0, reason: '没有分母就谈不上还差');
      expect(p.curriculumLabel, isNull);
    });

    test('★ 培养方案里课程代码为空的行按课程名对齐，两门无码课不许互相顶掉', () {
      // 真实培养方案里确实有代码为空的课程行；若一律拿 '' 当键，
      // 后一门会把前一门的已修学分顶掉（两门都变成「已修同一份」）。
      final plan = Curriculum(
        year: 2025,
        collegeName: 'X',
        majorName: 'Y',
        courses: [
          _course('', '无码必修甲', 2, '2024公共课', '公共数学课', CourseRequirement.compulsory),
          _course('', '无码必修乙', 3, '2024公共课', '公共数学课', CourseRequirement.compulsory),
        ],
      );
      final p = _build(
        curriculum: plan,
        taken: [
          _taken('', '无码必修甲', 2, 2),
          _taken('', '无码必修乙', 3, 0),
        ],
      );
      expect(p.compulsory.required, 5);
      expect(p.compulsory.earned, 2, reason: '只有甲拿到了学分');
      final jia = p.compulsory.courses.firstWhere((c) => c.name == '无码必修甲');
      final yi = p.compulsory.courses.firstWhere((c) => c.name == '无码必修乙');
      expect(jia.done, isTrue);
      expect(yi.done, isFalse);
    });

    test('二级分类为空的课归不到类时，理由要说得出来（不是空白引号）', () {
      final plan = Curriculum(
        year: 2025,
        collegeName: 'X',
        majorName: 'Y',
        courses: [
          _course('7770000001', '类别空课', 2, '2024专业教育课', '', CourseRequirement.elective),
        ],
      );
      final p = _build(
        curriculum: plan,
        taken: [_taken('7770000001', '类别空课', 2, 2)],
      );
      expect(p.unmatched.single.reason, '在培养方案里，但「课程类别」为空，判不出该归哪一项');
    });
  });

  group('选修进度 · 培养方案三类', () {
    test('公共外语：只算「选修」的公共外语课，必修的大学英语不计', () {
      final p = _build(
        taken: [
          _taken('1004600232', '大学英语I', 2, 2), // 必修
          _taken('1004601702', '六级英语专题', 2, 2), // 选修
        ],
      );
      final item = _item(p, '公共外语');
      expect(item.courses.map((c) => c.name), ['六级英语专题']);
      expect(item.earned, 2);
      expect(item.remaining, 0);
      expect(item.satisfied, isTrue);
      // 必修那边照收大学英语I
      expect(p.compulsory.doneCourses.map((c) => c.name), ['大学英语I']);
    });

    test('学科开放：要求 3 学分，池子 2 门共 6 学分', () {
      final p = _build(taken: [_taken('1004501303', '管理学原理', 3, 3)]);
      final item = _item(p, '学科开放');
      expect(item.required, 3);
      expect(item.earned, 3);
      expect(item.satisfied, isTrue);
      expect(item.poolCount, 2);
      expect(item.poolCredits, 6);
    });

    test('专业方向：要求 15 学分，修了 5 学分就还差 10', () {
      final p = _build(
        taken: [
          _taken('1014300422', 'Linux操作系统', 2, 2),
          _taken('1004703083', '数学建模', 3, 3),
        ],
      );
      final item = _item(p, '专业方向');
      expect(item.earned, 5);
      expect(item.remaining, 10);
      expect(item.satisfied, isFalse);
      expect(item.ratio, closeTo(5 / 15, 1e-9));
    });
  });

  group('选修进度 · 四个通识模块（靠通识课程库）', () {
    test('课外修的通识课按库里的模块入账', () {
      final p = _build(
        taken: [
          _taken('1004809771', '工艺美术简史', 1.5, 1.5),
          _taken('1004909711', '中华优秀传统文化概论', 1.5, 1.5),
          _taken('1602302940', '习近平外交思想(尔雅网络课程)', 0.5, 0.5),
        ],
      );
      expect(_item(p, '美育').earned, 1.5);
      final hist = _item(p, '历史、政治与社会');
      expect(hist.earned, 2, reason: '1.5 + 0.5（外校网课也算）');
      expect(hist.satisfied, isTrue);
      expect(hist.courses, hasLength(2));
    });

    test('旧课程代码也能查到（备注里的「原代码」）', () {
      final p = _build(taken: [_taken('1602300052', '《汉书》导读', 1, 1)]);
      expect(_item(p, '历史、政治与社会').earned, 1);
    });

    test('培养方案里那门必修通识课（写作与沟通I）不能顶通识选修', () {
      final p = _build(taken: [_taken('1004907141', '写作与沟通I', 1.5, 1.5)]);
      expect(_item(p, '哲学、思维与语言').earned, 0, reason: '它顶的是必修进度');
      expect(p.compulsory.doneCourses.map((c) => c.name), ['写作与沟通I']);
    });

    test('培养方案里性质为选修的通识课也能顶（库与培养方案互为补充）', () {
      // 直接把一门不在库里的课塞进培养方案通识模块位
      final plan = Curriculum(
        year: 2025,
        collegeName: 'X',
        majorName: 'Y',
        courses: [
          _course('9990000001', '自定义通识课', 2, '2024通识教育课', '美育', CourseRequirement.elective),
        ],
      );
      final p = _build(
        curriculum: plan,
        taken: [_taken('9990000001', '自定义通识课', 2, 2)],
      );
      expect(_item(p, '美育').earned, 2);
      expect(_item(p, '美育').satisfied, isTrue);
    });
  });

  group('溢出与合计口径', () {
    test('★ 某一项多修的学分不能顶另一项的缺口', () {
      final p = _build(
        taken: [
          // 学科开放要求 3，修 6（两门各 3）→ 溢出 3
          _taken('1004501303', '管理学原理', 3, 3),
          _taken('1004201913', '金融学', 3, 3),
        ],
      );
      final item = _item(p, '学科开放');
      expect(item.earned, 6, reason: '真实已修不截顶');
      expect(item.counted, 3, reason: '计入本项要截顶');
      expect(item.overflow, 3);
      expect(item.remaining, 0);
      // 溢出不许跑到美育去
      expect(_item(p, '美育').earned, 0);
      expect(_item(p, '美育').remaining, 2);
      expect(p.electiveRemaining, 28 - 3);
      expect(p.totalRemaining, closeTo(13.5 + 25, 1e-9));
    });

    test('合计 = 逐项 max(0, 要求-已修) 之和；教务的「合计」行只是显示用', () {
      final p = _build();
      expect(p.electiveRequired, 28);
      expect(p.electiveCounted, 0);
      expect(p.electiveRemaining, 28);
      expect(p.electives, hasLength(7), reason: '「合计」行不进分项列表');
    });

    test('全部满足时 remaining 归零、satisfied 置位', () {
      final p = _build(
        taken: [
          _taken('1004601702', '六级英语专题', 2, 2),
          _taken('1004809771', '工艺美术简史', 2, 2),
          _taken('1602302940', '习近平外交思想(尔雅网络课程)', 2, 2),
          _taken('1004909711', '中华优秀传统文化概论', 2, 2),
          _taken('1004501303', '管理学原理', 3, 3),
        ],
      );
      // 还差的只剩：哲学、思维与语言 2 + 科学、技术与方法 2 + 专业方向 15
      expect(p.satisfiedElectives.map((e) => e.title), [
        '2024公共外语选修课',
        '2024美育选修2学分',
        '2024历史、政治与社会选修2学分',
        '2024学科开放选修课',
      ]);
      expect(p.electiveRemaining, 19);
      expect(
        [for (final e in p.electives) if (!e.satisfied) e.title],
        [
          '2024科学、技术与方法选修2学分',
          '2024哲学、思维与语言选修2学分',
          '2024专业方向选修课',
        ],
      );
    });

    test('earnedTotal = 全部已修学分（含未归类），与成绩页合计对得上', () {
      final p = _build(
        taken: [
          _taken('1004600232', '大学英语I', 2, 2),
          _taken('9990000001', '某门两边都没有的课', 1, 1), // 两边都没有 → 未归类
        ],
      );
      expect(p.earnedTotal, 3);
      expect(p.unmatchedCredits, 1);
    });
  });

  group('未归类：照实列出来并说明原因', () {
    test('既不在培养方案也不在通识课程库', () {
      final p = _build(taken: [_taken('9990000001', '某门两边都没有的课', 1, 1)]);
      expect(p.unmatched, hasLength(1));
      expect(p.unmatched.single.course.name, '某门两边都没有的课');
      expect(p.unmatched.single.reason, contains('既不在本专业培养方案'));
    });

    test('★ 大学生安全教育不进「未归类」—— 它是**学校规定不计入总学分**', () {
      // 材料明文（assets/rules/text/r03a.md）：「大学生安全教育不计入总学分，
      // 但安排 16 学时必修课，作为毕业资格审核的依据」。从前它落进未归类、
      // 理由写成「两边都没有」——那是**不完整**的。
      final p = _build(taken: [_taken('1003000011', '大学生安全教育', 1, 1)]);
      expect(p.unmatched, isEmpty);
      expect(p.notCounted.map((c) => c.name), ['大学生安全教育']);
      expect(p.notCountedCredits, 1);
      expect(p.notes.join(), contains('不计入总学分'));
      expect(p.notes.join(), contains('毕业资格审核依据'));
      // 已修合计照旧含它（那只是「成绩单上一共拿到多少学分」）
      expect(p.earnedTotal, 1);
    });

    test('只按课程代码也能认出「不计入总学分」的课（课程名被改过的情况）', () {
      final p = _build(taken: [_taken('1003000011', '安全教育（新名）', 1, 1)]);
      expect(p.notCounted, hasLength(1));
      expect(p.unmatched, isEmpty);
    });

    test('培养方案里有、但教务要求表里没有这一项（专业限选课）', () {
      final p = _build(taken: [_taken('1014300999', '限选专题', 2, 2)]);
      expect(p.unmatched.single.reason, contains('专业限选课'));
      expect(p.unmatched.single.reason, contains('教务要求表里没有这一项'));
    });

    test('通识库归到了「发展指导课」，但教务没这项要求', () {
      final p = _build(taken: [_taken('1006001211', '地产与财富', 1.5, 1.5)]);
      expect(p.unmatched.single.reason, contains('发展指导课'));
    });

    test('在通识库里但那一行没有模块标签（源表真实缺口）', () {
      final p = _build(taken: [_taken('1004607181', '战后日本经济与社会', 1, 1)]);
      expect(p.unmatched.single.reason, contains('没有模块标签'));
    });
  });

  group('实践环节（培养方案第二张表 · 2026-10-08 加）', () {
    test('★ 军事训练只在实践环节表里 → 进实践环节，不再落进「未归类」', () {
      final p = _build(taken: [_taken('1305002302', '军事训练', 2, 2)]);
      expect(p.practice.available, isTrue);
      expect(p.practice.totalCount, 4);
      expect(p.practice.required, 18);
      expect(p.practice.earned, 2);
      expect(p.practice.remaining, 16);
      expect(p.practice.doneStages.map((s) => s.name), ['军事训练']);
      expect(
        p.unmatched.map((u) => u.course.name),
        isNot(contains('军事训练')),
        reason: '从前它就是因为「两边都没有」才进未归类',
      );
    });

    test('实践环节按代码对齐，未修的也留在分母里', () {
      final p = _build();
      expect(p.practice.earned, 0);
      expect(p.practice.doneCount, 0);
      expect(p.practice.pendingStages.map((s) => s.name), [
        '军事训练',
        '创新创业实践活动',
        '毕业实习',
        '毕业设计',
      ]);
      expect(p.practice.ratio, 0);
    });

    test('挂科记 0，该环节仍算未修', () {
      final p = _build(taken: [_taken('1314300058', '毕业设计', 8, 0)]);
      expect(p.practice.earned, 0);
      expect(p.practice.pendingStages.map((s) => s.name), contains('毕业设计'));
    });

    test('成绩缺代码时按环节名兜底', () {
      final p = _build(taken: [_taken('', '毕业实习', 4, 4)]);
      expect(p.practice.earned, 4);
    });

    test('★ grandRemaining = 必修 + 选修 + 实践环节', () {
      final p = _build(taken: [_taken('1305002302', '军事训练', 2, 2)]);
      expect(p.compulsory.remaining, 13.5);
      expect(p.electiveRemaining, 28);
      expect(p.practice.remaining, 16);
      expect(p.grandRemaining, closeTo(13.5 + 28 + 16, 1e-9));
    });

    test('实践环节表拿不到 → available=false + 明说，不假装 0', () {
      final p = _build(withPractice: false);
      expect(p.practice.available, isFalse);
      expect(p.practice.satisfied, isFalse);
      expect(p.practice.label, isNull);
      expect(p.notes.join(), contains('实践环节表拿不到'));
      // 军事训练没地方去了 → 回落到未归类（不会凭空消失）
      final p2 = _build(
        withPractice: false,
        taken: [_taken('1305002302', '军事训练', 2, 2)],
      );
      expect(p2.unmatched.map((u) => u.course.name), contains('军事训练'));
    });

    test('两张表都出现的课按理论课程计入必修，不重复计入实践环节，并给出提示', () {
      // 造一个「劳育I 同时在理论课程（必修）与实践环节里」的重叠
      final plan = Curriculum(
        year: 2025,
        collegeName: 'X',
        majorName: 'Y',
        courses: [
          _course('1005202771', '劳育I', 1, '2024实践教育课', '劳动教育', CourseRequirement.compulsory),
        ],
      );
      final practice = const PracticeCurriculum(
        year: 2025,
        collegeName: 'X',
        majorName: 'Y',
        stages: [
          PracticeStage(index: 1, code: '1005202771', name: '劳育I', credit: 1),
          PracticeStage(index: 2, code: '1305002302', name: '军事训练', credit: 2),
        ],
      );
      final p = _build(
        curriculum: plan,
        practice: practice,
        taken: [
          _taken('1005202771', '劳育I', 1, 1),
          _taken('1305002302', '军事训练', 2, 2),
        ],
      );
      expect(p.compulsory.earned, 1, reason: '重叠课计入必修');
      expect(p.practice.required, 3);
      expect(p.practice.earned, 2, reason: '只算军事训练，劳育I 不重复计入');
      expect(p.notes.join(), contains('同时出现在理论课程与实践环节表里'));
      expect(p.notes.join(), contains('劳育I'));
    });
  });

  group('已选未考（本学期在修 · 2026-10-08 加）', () {
    test('★ 在修只占位、不产生获得学分、也不冲抵「还差」', () {
      final p = _build(
        inProgress: [
          _taken('1004701034', '高等数学I', 4, 0),
          _taken('1014300154', '程序设计基础', 4, 0),
        ],
      );
      expect(p.compulsory.earned, 0, reason: '在修不算已修');
      expect(p.compulsory.inProgress, 8);
      expect(p.compulsory.remaining, 13.5, reason: '还差只按已拿到手的算');
      expect(p.inProgressTotal, 8);
      // 比例：已修 0，在修 8/13.5
      expect(p.compulsory.ratio, 0);
      expect(p.compulsory.inProgressRatio, closeTo(8 / 13.5, 1e-9));
    });

    test('在修的必修课在明细里标得出来', () {
      final p = _build(inProgress: [_taken('1004701034', '高等数学I', 4, 0)]);
      final gs = p.compulsory.courses.firstWhere((c) => c.name == '高等数学I');
      expect(gs.inProgress, isTrue);
      expect(gs.done, isFalse);
      expect(gs.earned, 0);
      // 没在修的不受影响
      final yy = p.compulsory.courses.firstWhere((c) => c.name == '大学英语I');
      expect(yy.inProgress, isFalse);
    });

    test('★ 在修与已修不重复：同一门课既有成绩又在课表里，只算已修', () {
      final p = _build(
        taken: [_taken('1004701034', '高等数学I', 4, 4)],
        inProgress: [_taken('1004701034', '高等数学I', 4, 0)],
      );
      expect(p.compulsory.earned, 4);
      // 在修那批是上层 provider 过滤过的（有成绩就不该进在修），
      // 但即便传进来，明细也以「已修」为准
      final gs = p.compulsory.courses.firstWhere((c) => c.name == '高等数学I');
      expect(gs.done, isTrue);
    });

    test('选修项也能标在修', () {
      final p = _build(inProgress: [_taken('1004601702', '六级英语专题', 2, 0)]);
      final item = _item(p, '公共外语');
      expect(item.earned, 0);
      expect(item.inProgress, 2);
      expect(item.inProgressCounted, 2);
      expect(item.inProgressCourses.map((c) => c.name), ['六级英语专题']);
      expect(item.remaining, 2, reason: '在修不冲抵缺口');
    });

    test('在修超出本项容量时截顶（不越过要求值）', () {
      final p = _build(
        inProgress: [
          _taken('1004601702', '六级英语专题', 2, 0),
          _taken('1004606282', '考研英语专题', 2, 0),
        ],
      );
      final item = _item(p, '公共外语'); // 要求 2
      expect(item.inProgress, 4);
      expect(item.inProgressCounted, 2);
      expect(item.inProgressRatio, closeTo(1, 1e-9));
    });

    test('实践环节也能标在修', () {
      final p = _build(inProgress: [_taken('1305002302', '军事训练', 2, 0)]);
      expect(p.practice.earned, 0);
      expect(p.practice.inProgress, 2);
      expect(p.practice.pendingStages.map((s) => s.name), contains('军事训练'));
      final stage = p.practice.stages.firstWhere((s) => s.name == '军事训练');
      expect(stage.inProgress, isTrue);
    });

    test('在修课归不到任何要求项时静默跳过，不进「未归类」', () {
      final p = _build(inProgress: [_taken('1003000011', '大学生安全教育', 1, 0)]);
      expect(p.unmatched, isEmpty, reason: '还没出成绩，谈不上归错类');
      expect(p.inProgressTotal, 0);
    });

    test('一门都没在修 → inProgress 全 0，比例也是 0（界面就不画浅色段）', () {
      final p = _build();
      expect(p.inProgressTotal, 0);
      expect(p.compulsory.inProgressRatio, 0);
      expect(p.practice.inProgressRatio, 0);
      expect(_item(p, '美育').inProgressRatio, 0);
    });
  });

  group('挂科（不及格即使已修也算未获得学分 · 2026-10-08 加）', () {
    // ⚠ 本组**全部用合成数据**：真实账号没有挂科记录（用户原话：「测试时不能用
    // 我的数据测了，我没有挂科记录」），所以真实数据侧永远走不到这些分支。
    test('★ 挂科不计入已修，且仍然留在「还差」里', () {
      final p = _build(
        taken: [
          _taken('1004701034', '高等数学I', 4, 0, score: 52), // 挂
          _taken('1004600232', '大学英语I', 2, 2), // 过
        ],
      );
      // 已修只算过的那门
      expect(p.compulsory.earned, 2);
      expect(p.compulsory.doneCount, 1);
      // 挂掉的 4 学分没拿到 → 缺口照算
      expect(p.compulsory.remaining, closeTo(13.5 - 2, 1e-9));
      expect(p.hasFailed, isTrue);
      expect(p.failedCredits, 4);
      expect(p.failedCourses.map((c) => c.name), ['高等数学I']);
      expect(p.failedCourses.single.scoreText, '52');
    });

    test('明细里那门课标成「挂科」而不是「未修」', () {
      final p = _build(taken: [_taken('1004701034', '高等数学I', 4, 0, score: 52)]);
      final gs = p.compulsory.courses.firstWhere((c) => c.name == '高等数学I');
      expect(gs.failed, isTrue);
      expect(gs.done, isFalse);
      expect(gs.inProgress, isFalse);
    });

    test('★ 挂科 ≠ 在修：没成绩的课不会因为挂过就被当成在修，反之亦然', () {
      final p = _build(
        taken: [_taken('1004701034', '高等数学I', 4, 0, score: 52)],
        inProgress: [_taken('1014300154', '程序设计基础', 4, 0)],
      );
      final gs = p.compulsory.courses.firstWhere((c) => c.name == '高等数学I');
      final cx = p.compulsory.courses.firstWhere((c) => c.name == '程序设计基础');
      expect(gs.failed, isTrue);
      expect(gs.inProgress, isFalse);
      expect(cx.failed, isFalse, reason: '在修没有成绩，不该算挂科');
      expect(cx.inProgress, isTrue);
      expect(p.failedCourses.map((c) => c.name), ['高等数学I']);
      expect(p.compulsory.inProgress, 4);
    });

    test('重修通过后不再是挂科（同码取获得学分更高的那条）', () {
      final p = _build(
        taken: [
          _taken('1004701034', '高等数学I', 4, 0, score: 52, semester: '251'),
          _taken('1004701034', '高等数学I', 4, 4, score: 78, semester: '252'),
        ],
      );
      expect(p.hasFailed, isFalse);
      expect(p.failedCredits, 0);
      expect(p.compulsory.earned, 4);
      expect(p.notes.any((n) => n.contains('挂科')), isFalse);
    });

    test('选修项里的挂科也算（不是只看必修）', () {
      final p = _build(taken: [_taken('1004601702', '六级英语专题', 2, 0, score: 55)]);
      expect(p.hasFailed, isTrue);
      expect(p.failedCourses.single.name, '六级英语专题');
      expect(_item(p, '公共外语').earned, 0);
    });

    test('实践环节挂科也算', () {
      final p = _build(taken: [_taken('1305002302', '军事训练', 2, 0)]);
      expect(p.hasFailed, isTrue);
      expect(p.failedCourses.single.name, '军事训练');
      expect(p.practice.earned, 0);
      expect(p.practice.stages.first.failed, isTrue);
    });

    test('没挂科时 hasFailed=false，脚注里也不出现「挂科」', () {
      final p = _build(taken: [_taken('1004600232', '大学英语I', 2, 2)]);
      expect(p.hasFailed, isFalse);
      expect(p.failedCourses, isEmpty);
      expect(p.failedCredits, 0);
      expect(p.notes.any((n) => n.contains('挂科')), isFalse);
    });

    test('★ 挂科会在口径脚注里点名（上屏可解释）', () {
      final p = _build(
        taken: [
          _taken('1004701034', '高等数学I', 4, 0, score: 52),
          _taken('1004600232', '大学英语I', 2, 0, score: 41),
        ],
      );
      final note = p.notes.firstWhere((n) => n.contains('挂科'));
      expect(note, contains('2 门'));
      expect(note, contains('高等数学I'));
      expect(note, contains('大学英语I'));
      expect(note, contains('不计入已修学分'));
      expect(note, contains('重修'));
    });

    test('学分是 0 的课不会被判成挂科（避免除零类噪音）', () {
      final p = _build(taken: [_taken('9990000001', '零学分讲座', 0, 0)]);
      expect(p.hasFailed, isFalse);
    });
  });

  group('降级：拿不到某一路数据时不许假装算出来了', () {
    test('没有通识课程库 → 四个通识模块仍显示要求值，已修为 0', () {
      final p = buildGraduationCreditProgress(
        requirements: _requirements,
        taken: [_taken('1004809771', '工艺美术简史', 1.5, 1.5)],
        curriculum: _curriculum,
        practice: _practice,
        catalog: GeneralEducationCatalog.empty,
        cohort: 2025,
      );
      expect(_item(p, '美育').required, 2);
      expect(_item(p, '美育').earned, 0);
      // 课程没地方去 → 未归类，而不是被静默丢掉
      expect(p.unmatched.single.course.name, '工艺美术简史');
      expect(p.catalogScope!.sheets, isEmpty);
      expect(p.notes.join(), contains('通识课程库为空'));
    });

    test('没有培养方案 → 三类专业选修算不出来，但通识模块照算', () {
      final p = _build(
        withCurriculum: false,
        taken: [
          _taken('1004809771', '工艺美术简史', 2, 2),
          _taken('1004501303', '管理学原理', 3, 3),
        ],
      );
      expect(_item(p, '美育').earned, 2, reason: '通识只依赖课程库');
      expect(_item(p, '学科开放').earned, 0, reason: '学科开放只认培养方案');
      expect(p.unmatched.single.course.name, '管理学原理');
      expect(p.notes.join(), contains('培养方案拿不到'));
    });

    test('学校还没下发该年级的通识库表 → 退到最新一张并在 notes 里说明', () {
      final p = buildGraduationCreditProgress(
        requirements: _requirements,
        taken: const [],
        curriculum: _curriculum,
        catalog: _catalog(),
        cohort: 2030,
      );
      expect(p.catalogScope!.exactCohortMatch, isFalse);
      expect(p.notes.join(), contains('没有适用 2030 级'));
      // 退到最新那张 = 校内库（cohortTo 2025）
      expect(
        p.catalogScope!.sheets.first.title,
        contains('2024-2025'),
      );
    });

    test('学籍入学年未知时也能算，并说明按哪张表查的', () {
      final p = buildGraduationCreditProgress(
        requirements: _requirements,
        taken: [_taken('1004809771', '工艺美术简史', 2, 2)],
        curriculum: _curriculum,
        catalog: _catalog(),
      );
      expect(p.catalogScope!.cohort, isNull);
      expect(p.catalogScope!.exactCohortMatch, isFalse);
      expect(_item(p, '美育').earned, 2);
      expect(p.notes.join(), contains('入学年未知'));
    });

    test('一条成绩都没有 → 全 0，不炸', () {
      final p = _build();
      expect(p.earnedTotal, 0);
      expect(p.unmatched, isEmpty);
      expect(p.totalRemaining, closeTo(13.5 + 28, 1e-9));
    });
  });
}
