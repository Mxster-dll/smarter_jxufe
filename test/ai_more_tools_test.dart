import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ai/data/ai_chat_controller.dart';
import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/ai/tools/life_tools.dart';
import 'package:smarter_jxufe/features/ai/tools/plan_tools.dart';
import 'package:smarter_jxufe/features/ai/tools/tool_registry.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/volunteer_hours_providers.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/assessment_method.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_nature.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_requirement.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/credit_hour.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/my_curriculum_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/providers/credit_progress_provider.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/credit_progress.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/graduation_requirement.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/presentation/graduation_requirements_screen.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_calendar_providers.dart';
// 学年 / 假期（`SchoolTimeTable` 由它 export）。
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_time_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_store.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

/// 一批工具（培养方案 / 毕业学分 / 志愿 / 综测 / 材料 / 校历）的取数与文案。
///
/// 全部靠 override 底层 provider 来测 —— 这样不碰真网络，
/// 测的就是**工具自己的聚合与措辞**。
/// ⚠ 例外 = 末尾的 `get_zongce` 组：综测的手动项要经 `ZcStore`（Hive）读，
/// 那一组在临时目录里 `Hive.init` 出一个真 box（连同两个自动源一起 stub），
/// 仍然不碰网络。

/// 借一个返回自身的 Provider 把真实 `Ref` 取出来。
AiToolContext contextWith(ProviderContainer container, {DateTime? now}) =>
    AiToolContext(
      ref: container.read(Provider<Ref>((ref) => ref)),
      gate: const AiDenyWriteGate(),
      now: now ?? DateTime(2026, 10, 15, 14, 30),
    );

Course course({
  required String code,
  required String name,
  required double credit,
  required String mainCategory,
  String subCategory = '',
  CourseRequirement requirement = CourseRequirement.compulsory,
}) => Course(
  code: code,
  name: name,
  credit: credit,
  creditHour: const CreditHour(total: 64, lecture: 64, weekly: 4),
  mainCategory: mainCategory,
  subCategory: subCategory,
  tertiaryCategory: null,
  requirement: requirement,
  nature: CourseNature.values.first,
  importance: CourseImportance.values.first,
  assessmentMethod: AssessmentMethod.values.first,
  identification: '',
);

void main() {
  group('工具注册表（第二组）', () {
    test('新工具都挂上了，且总数对得上', () {
      final names = kAllAiTools.map((t) => t.spec.name).toList();
      for (final n in const [
        'get_curriculum',
        'get_graduation_credits',
        'get_volunteer_hours',
        'get_zongce',
        'list_materials',
        'get_school_calendar',
        'get_energy',
      ]) {
        expect(names, contains(n));
      }
      // 12 个原有 + 7 个新增。数字本身不重要，重要的是**有人动清单时这里会红**。
      expect(names.length, 19);
      expect(names.toSet().length, 19, reason: '工具名不能重复');
    });

    test('每个新工具的中文动作名都登记了（界面上会显示这行字）', () {
      final labels = kAiToolLabels;
      for (final t in kAllAiTools) {
        expect(labels.containsKey(t.spec.name), isTrue,
            reason: '缺 ${t.spec.name} 的中文动作名');
      }
    });

    test('无参工具（get_energy）的 schema 仍是合法 object', () {
      final tool = aiToolByName('get_energy')!;
      expect(tool.spec.parameters['type'], 'object');
      expect(tool.spec.parameters['properties'], isA<Map<dynamic, dynamic>>());
    });
  });

  group('get_curriculum', () {
    Curriculum plan() => Curriculum(
      year: 2023,
      collegeName: '软件与物联网工程学院',
      majorName: '软件工程',
      courses: [
        course(
          code: '1001',
          name: '高等数学I',
          credit: 5,
          mainCategory: '通识必修课',
        ),
        course(
          code: '1002',
          name: '大学英语I',
          credit: 3,
          mainCategory: '通识必修课',
        ),
        course(
          code: '2001',
          name: '数据结构',
          credit: 4,
          mainCategory: '专业必修课',
        ),
        course(
          code: '3001',
          name: '摄影鉴赏',
          credit: 1,
          mainCategory: '通识选修课',
          requirement: CourseRequirement.elective,
        ),
      ],
    );

    ProviderContainer withPlan(Curriculum? value) => ProviderContainer(
      overrides: [aiCurriculumProvider.overrideWith((ref) async => value)],
    );

    test('总账用**全量**算（筛选只影响清单，不影响「总共要修多少」）', () async {
      final container = withPlan(plan());
      addTearDown(container.dispose);

      final r = await const GetCurriculumTool().run(
        contextWith(container),
        {'course': '高等数学'},
      );
      final text = r.content;
      // 整数不带小数点（13.0 → 13），与 _trim 口径一致
      expect(text, contains('共 4 门课 / 13 学分'));
      expect(text, contains('通识必修课：2 门 / 8 学分'));
      expect(text, contains('专业必修课：1 门 / 4 学分'));
      // 筛选后只列 1 门
      expect(text, contains('高等数学I'));
      expect(text, isNot(contains('数据结构')));
      expect(text, contains('名称或代码含「高等数学」'));
    });

    test('清单按学分从高到低，limit 截断时明说', () async {
      final container = withPlan(plan());
      addTearDown(container.dispose);

      final r = await const GetCurriculumTool().run(contextWith(container), {
        'limit': 2,
      });
      final text = r.content;
      expect(text, contains('只列学分最高的 2 门'));
      final first = text.indexOf('· 高等数学I');
      final second = text.indexOf('· 数据结构');
      expect(first, greaterThanOrEqualTo(0));
      expect(second, greaterThan(first));
      // 排第三的（学分 3）不该出现
      expect(text, isNot(contains('大学英语I')));
    });

    test('按修读性质筛选', () async {
      final container = withPlan(plan());
      addTearDown(container.dispose);

      final r = await const GetCurriculumTool().run(contextWith(container), {
        'requirement': '选修课',
      });
      expect(r.content, contains('摄影鉴赏'));
      expect(r.content, isNot(contains('数据结构')));
    });

    test('拿不到培养方案时**如实报错**，不编造', () async {
      final container = withPlan(null);
      addTearDown(container.dispose);

      final r = await const GetCurriculumTool().run(contextWith(container), {});
      expect(r.ok, isFalse);
      expect(r.content, contains('拿不到本专业的培养方案'));
    });
  });

  group('get_graduation_credits', () {
    // ⚠ 这一组**必须**把 `myStudentInfoProvider` 一起 override 掉：不 override 时
    // 它会去 `Hive.openBox('studentInfo')`，而本组没有 `Hive.init` →
    // `HiveError: You need to initialize Hive…` 会被 flutter_test 当成未捕获错误打红
    // （哪怕调用方 try/catch 接住了，Riverpod 仍会往 zone 报一次）。
    // `graduationInProgressProvider` 同理（它会读课表缓存 box）→ 直接给空表。
    ProviderContainer withReqs(
      List<GraduationRequirement> rows, {
      Curriculum? curriculum,
      List<TakenCourse> taken = const [],
    }) => ProviderContainer(
      overrides: [
        graduationRequirementsProvider.overrideWith((ref) async => rows),
        myStudentInfoProvider.overrideWith((ref) async => null),
        myCurriculumProvider.overrideWith((ref) async => curriculum),
        graduationTakenCoursesProvider.overrideWith((ref) async => taken),
        graduationInProgressProvider.overrideWith((ref) async => const []),
      ],
    );

    test('逐项给出「要求 / 已修 / 还差」与判定口径；「合计」行不当分项列', () async {
      final container = withReqs(const [
        GraduationRequirement(index: 1, item: '通识必修课', credit: 40),
        GraduationRequirement(index: 2, item: '专业必修课', credit: 60),
        GraduationRequirement(
          index: 3,
          item: '合计',
          credit: 100,
          isTotal: true,
        ),
      ]);
      addTearDown(container.dispose);

      final r = await const GetGraduationCreditsTool().run(
        contextWith(container),
        {},
      );
      expect(r.ok, isTrue);
      expect(r.content, contains('通识必修课：要求 40 学分'));
      expect(r.content, contains('专业必修课：要求 60 学分'));
      expect(r.content, isNot(contains('合计：')), reason: '「合计」行不是分项');
    });

    test('没有「合计」行时，选修汇总行给的就是各分项之和', () async {
      final container = withReqs(const [
        GraduationRequirement(index: 1, item: '通识必修课', credit: 40.5),
        GraduationRequirement(index: 2, item: '专业必修课', credit: 60),
      ]);
      addTearDown(container.dispose);

      final r = await const GetGraduationCreditsTool().run(
        contextWith(container),
        {},
      );
      expect(r.content, contains('要求 100.5 学分'));
      expect(r.content, contains('还差 100.5 学分'));
    });

    test('拿不到培养方案时，必修如实说「无法统计」而不是 0', () async {
      final container = withReqs(const [
        GraduationRequirement(index: 1, item: '2024美育选修2学分', credit: 2),
      ]);
      addTearDown(container.dispose);

      final r = await const GetGraduationCreditsTool().run(
        contextWith(container),
        {},
      );
      expect(r.content, contains('必修课：拿不到本专业培养方案，无法统计'));
    });

    test('★ 有培养方案 + 成绩时给出必修与选修的真实进度', () async {
      final container = withReqs(
        const [
          GraduationRequirement(index: 1, item: '2024公共外语选修课', credit: 2),
          GraduationRequirement(index: 2, item: '2024学科开放选修课', credit: 3),
        ],
        curriculum: Curriculum(
          year: 2025,
          collegeName: '计算机与人工智能学院',
          majorName: '计算机科学与技术',
          courses: [
            course(
              code: '1004600232',
              name: '大学英语I',
              credit: 2,
              mainCategory: '2024公共课',
              subCategory: '公共外语课',
            ),
            course(
              code: '1004701034',
              name: '高等数学I',
              credit: 4,
              mainCategory: '2024公共课',
              subCategory: '公共数学课',
            ),
            course(
              code: '1004601702',
              name: '六级英语专题',
              credit: 2,
              mainCategory: '2024公共课',
              subCategory: '公共外语课',
              requirement: CourseRequirement.elective,
            ),
            course(
              code: '1004501303',
              name: '管理学原理',
              credit: 3,
              mainCategory: '2024专业教育课',
              subCategory: '学科开放课',
              requirement: CourseRequirement.elective,
            ),
          ],
        ),
        taken: const [
          TakenCourse(code: '1004600232', name: '大学英语I', credit: 2, earned: 2),
          TakenCourse(code: '1004601702', name: '六级英语专题', credit: 2, earned: 2),
        ],
      );
      addTearDown(container.dispose);

      final r = await const GetGraduationCreditsTool().run(
        contextWith(container),
        {},
      );
      expect(r.ok, isTrue);
      // 必修：要求 2 + 4 = 6，已修 2 → 还差 4，1/2 门
      expect(r.content, contains('必修课：已修 2 / 要求 6 学分，还差 4 学分（1/2 门）'));
      // 公共外语：要求 2，已修 2 → 已满足
      expect(r.content, contains('2024公共外语选修课：要求 2 学分，已修 2 学分，已满足'));
      // 学科开放：要求 3，已修 0 → 还差 3
      expect(r.content, contains('2024学科开放选修课：要求 3 学分，已修 0 学分，还差 3 学分'));
      // 口径要带上，方便模型解释「为什么这门课算这一项」
      expect(r.content, contains('培养方案「公共外语课」'));
    });

    test('item 过滤只留匹配的分项', () async {
      final container = withReqs(const [
        GraduationRequirement(index: 1, item: '2024美育选修2学分', credit: 2),
        GraduationRequirement(index: 2, item: '2024学科开放选修课', credit: 3),
      ]);
      addTearDown(container.dispose);

      final r = await const GetGraduationCreditsTool().run(contextWith(container), {
        'item': '美育',
      });
      expect(r.content, contains('2024美育选修2学分'));
      expect(r.content, isNot(contains('2024学科开放选修课：')));
    });

    test('取不到时提示要教务会话', () async {
      final container = ProviderContainer(
        overrides: [
          graduationRequirementsProvider.overrideWith(
            (ref) async => throw Exception('JSESSIONID 为空'),
          ),
          myStudentInfoProvider.overrideWith((ref) async => null),
          myCurriculumProvider.overrideWith((ref) async => null),
          graduationTakenCoursesProvider.overrideWith((ref) async => const []),
          graduationInProgressProvider.overrideWith((ref) async => const []),
        ],
      );
      addTearDown(container.dispose);

      final r = await const GetGraduationCreditsTool().run(
        contextWith(container),
        {},
      );
      expect(r.ok, isFalse);
      expect(r.content, contains('教务会话'));
    });
  });

  group('get_volunteer_hours', () {
    VolunteerActivity act(String name, String hours, String date) =>
        VolunteerActivity(
          index: 1,
          activityName: name,
          initiator: '校团委',
          responsiblePerson: '张老师',
          department: '软件与物联网工程学院',
          activityCategory: '志愿服务',
          recognizedHours: hours,
          applicationStatus: '已通过',
          recognitionStatus: '已认定',
          detailId: '1',
          detailType: '1',
          startDate: date,
          endDate: date,
        );

    ProviderContainer withActs(List<VolunteerActivity> acts) =>
        ProviderContainer(
          overrides: [
            volunteerActivitiesProvider.overrideWith((ref) async => acts),
          ],
        );

    test('本学年 = 教学学年（9/1 ~ 次年 8/31），别拿总时长冒充', () async {
      // ctx.now = 2026-10-15 → 教学学年 xn = 2026
      final container = withActs([
        act('迎新志愿', '10', '2026-10-01'), // 本学年
        act('校运会', '6', '2026-11-20'), // 本学年
        act('去年的活动', '8', '2025-12-12'), // 上学年
      ]);
      addTearDown(container.dispose);

      final r = await const GetVolunteerHoursTool().run(
        contextWith(container),
        {},
      );
      expect(r.content, contains('累计 24 小时'));
      expect(r.content, contains('本学年（2026-2027学年）：16 小时'));
      expect(r.content, contains('上一学年：8 小时'));
    });

    test('一条日期都取不到 → 本学年显示「—」而不是 0', () async {
      final container = withActs([act('无日期活动', '12', '')]);
      addTearDown(container.dispose);

      final r = await const GetVolunteerHoursTool().run(
        contextWith(container),
        {},
      );
      expect(r.content, contains('累计 12 小时'));
      expect(r.content, contains('—'));
      expect(r.content, isNot(contains('本学年（2026-2027学年）：0')));
    });

    test('未登录（provider 抛错）时如实回报', () async {
      final container = ProviderContainer(
        overrides: [
          volunteerActivitiesProvider.overrideWith(
            (ref) async => throw Exception('请先登录后再查看志愿服务时长'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final r = await const GetVolunteerHoursTool().run(
        contextWith(container),
        {},
      );
      expect(r.ok, isFalse);
      expect(r.content, contains('请先登录'));
    });
  });

  group('list_materials', () {
    ProviderContainer withMats(List<ZcMaterial> mats) => ProviderContainer(
      overrides: [zcMaterialsProvider.overrideWith((ref) async => mats)],
    );

    test('按材料类型分组（组标题 = 类型名 · 条数）', () async {
      final container = withMats(const [
        ZcMaterial(
          id: 'a',
          typeId: ZcTypeId.contest,
          name: '蓝桥杯省一',
          dateIso: '2026-05-01',
        ),
        ZcMaterial(
          id: 'b',
          typeId: ZcTypeId.contest,
          name: '数学建模国二',
          dateIso: '2026-09-01',
        ),
        ZcMaterial(
          id: 'c',
          typeId: ZcTypeId.foreign,
          name: '大学英语四级',
          dateIso: '2025-12-01',
          manualScore: 489,
        ),
      ]);
      addTearDown(container.dispose);

      final r = await const ListMaterialsTool().run(contextWith(container), {});
      expect(r.content, contains('材料库共 3 条'));
      expect(r.content, contains('学科竞赛获奖】2 条'));
      expect(r.content, contains('外语水平】1 条'));
      // 外语材料的原始成绩要带上（综测按档位换算要用它）
      expect(r.content, contains('原始成绩 489'));
    });

    test('按年份过滤', () async {
      final container = withMats(const [
        ZcMaterial(
          id: 'a',
          typeId: ZcTypeId.contest,
          name: '2026 年的奖',
          dateIso: '2026-05-01',
        ),
        ZcMaterial(
          id: 'b',
          typeId: ZcTypeId.contest,
          name: '2025 年的奖',
          dateIso: '2025-05-01',
        ),
      ]);
      addTearDown(container.dispose);

      final r = await const ListMaterialsTool().run(contextWith(container), {
        'year': 2025,
      });
      expect(r.content, contains('2025 年的奖'));
      expect(r.content, isNot(contains('2026 年的奖')));
      expect(r.content, contains('本地总共 2 条'));
    });

    test('材料库为空时说清楚是空的', () async {
      final container = withMats(const []);
      addTearDown(container.dispose);

      final r = await const ListMaterialsTool().run(contextWith(container), {});
      expect(r.content, contains('还没有材料'));
    });
  });

  group('get_school_calendar', () {
    /// 2026-10：1~7 号标非工作日（国庆），9 号再单独标一天（断开 → 两段）。
    SchoolCalendar cal() => SchoolCalendar(
      title: '2026-2027学年第一学期校历',
      xn: 2026,
      xq: 0,
      notes: const ['10 月 8 日（周四）补 10 月 6 日（周二）的课'],
      months: [
        CalendarMonth(
          year: 2026,
          month: 10,
          rows: [
            CalendarWeekRow(
              weekNo: '5',
              days: const [1, 2, 3, 4, 5, 6, 7],
              kinds: const [
                CalendarDayKind.nonday,
                CalendarDayKind.nonday,
                CalendarDayKind.nonday,
                CalendarDayKind.nonday,
                CalendarDayKind.nonday,
                CalendarDayKind.nonday,
                CalendarDayKind.nonday,
              ],
            ),
            CalendarWeekRow(
              weekNo: '6',
              days: const [8, 9, 10, 11, 12, 13, 14],
              kinds: const [
                CalendarDayKind.workday,
                CalendarDayKind.nonday,
                null,
                null,
                null,
                null,
                null,
              ],
            ),
          ],
        ),
      ],
    );

    ProviderContainer withCal(SchoolCalendar? value) => ProviderContainer(
      overrides: [
        schoolCalendarProvider.overrideWith((ref, arg) async => value!),
        teachingWeekProvider.overrideWith((ref) async => null),
      ],
    );

    test('连续的非工作日合并成区间（7 天 → 1 条；断开的 9 号 → 第 2 条）', () async {
      final container = withCal(cal());
      addTearDown(container.dispose);

      final r = await const GetSchoolCalendarTool().run(
        contextWith(container),
        {},
      );
      expect(r.content, contains('2026-10-01 ~ 10-07（7 天）'));
      expect(r.content, contains('2026-10-09（1 天）'));
      expect(r.content, contains('非工作日区间'));
      // 备注要带出来（调休安排只在备注里）
      expect(r.content, contains('补 10 月 6 日'));
    });

    test('只要某个月时不串月', () async {
      final container = withCal(cal());
      addTearDown(container.dispose);

      final r = await const GetSchoolCalendarTool().run(contextWith(container), {
        'month': 11,
      });
      expect(r.content, contains('11 月没有标出非工作日'));
    });

    test('校历读不到时如实报错', () async {
      final container = ProviderContainer(
        overrides: [
          schoolCalendarProvider.overrideWith(
            (ref, arg) async => throw Exception('校历服务不可用'),
          ),
          teachingWeekProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      final r = await const GetSchoolCalendarTool().run(
        contextWith(container),
        {},
      );
      expect(r.ok, isFalse);
      expect(r.content, contains('校历读取失败'));
    });
  });

  group('get_school_calendar · 学年（用户 2026-09-27：「上一学年的最后一天是？」）', () {
    /// 一条备注（`school_time.dart` 认「学期/假期 + 开始/结束日期」四行）。
    SchoolCalendar calOf(int xn, int xq, List<String> notes) => SchoolCalendar(
      title: '$xn-$xq 校历',
      xn: xn,
      xq: xq,
      notes: notes,
      months: const [],
    );

    /// 2025-2026 学年的真实台账（教务校历页实测）：第一学期 09-01 起，
    /// 第二学期 03-02 起，暑期段 07-06~07-10，暑假到 2026-09-06（下学年 09-07 开学）。
    SchoolTimeTable table2025() => SchoolTimeTable.fromCalendars([
      calOf(2025, 0, const [
        '学期开始日期：2025-09-01',
        '学期结束日期：2026-01-15',
        '假期开始日期：2026-01-16',
        '假期结束日期：2026-03-01',
      ]),
      calOf(2025, 1, const [
        '学期开始日期：2026-03-02',
        '学期结束日期：2026-07-05',
      ]),
      calOf(2025, 2, const [
        '学期开始日期：2026-07-06',
        '学期结束日期：2026-07-10',
        '假期开始日期：2026-07-11',
        '假期结束日期：2026-09-06',
      ]),
      calOf(2026, 0, const ['学期开始日期：2026-09-07']),
    ]);

    ProviderContainer withTable(SchoolTimeTable table) => ProviderContainer(
      overrides: [
        schoolCalendarProvider.overrideWith(
          (ref, arg) async => calOf(arg.xn, arg.xq, const []),
        ),
        teachingWeekProvider.overrideWith((ref) async => null),
        schoolTimeTableProvider.overrideWith((ref, xn) async => table),
      ],
    );

    test('★ 上一学年的最后一天 = 下学年第一学期第一天 − 1 天（2026-09-06）', () async {
      final container = withTable(table2025());
      addTearDown(container.dispose);

      final r = await const GetSchoolCalendarTool().run(contextWith(container), {
        'xn': 2025,
        'xq': 0,
      });
      expect(r.ok, isTrue);
      expect(r.content, contains('学年：2025-2026学年 = 2025-09-01 ~ 2026-09-06'));
      // 寒假 / 暑假区间一并给出（结束侧同样是派生的）
      expect(r.content, contains('寒假：2026-01-16 ~ 2026-03-01'));
      expect(r.content, contains('暑假：2026-07-11 ~ 2026-09-06'));
      // ★ 回归：模型当初按「9/1 ~ 次年 8/31」硬推的 08-31 **一个都不许出现**
      //   （8/31 只是 `schoolYearFallback` 的兜底值，有校历时不该用它）。
      expect(r.content, isNot(contains('2026-08-31')));
    });

    test('下学年校历未公布 → 结束日留空并明确「别当成 8 月 31 日」', () async {
      final table = SchoolTimeTable.fromCalendars([
        calOf(2026, 0, const ['学期开始日期：2026-09-07']),
      ]);
      final container = withTable(table);
      addTearDown(container.dispose);

      final r = await const GetSchoolCalendarTool().run(contextWith(container), {
        'xn': 2026,
      });
      expect(r.content, contains('学年：2026-2027学年 = 2026-09-07 起'));
      expect(r.content, contains('别当成 8 月 31 日'));
      expect(r.content, isNot(contains('2027-08-31')));
    });

    test('校历整年没公布 → 说「起止日未知」，不编日期', () async {
      final container = withTable(SchoolTimeTable.empty);
      addTearDown(container.dispose);

      final r = await const GetSchoolCalendarTool().run(contextWith(container), {
        'xn': 2026,
      });
      expect(r.content, contains('校历还没公布，起止日未知'));
    });
  });

  group('get_zongce（综测数据源 · 用户 2026-09-27：「给这个模块接入 ai 助手的数据源」）', () {
    late Directory dir;
    late Box<String> box;
    late ZcStore store;

    setUpAll(() async {
      dir = Directory.systemTemp.createTempSync('ai_zongce_test');
      Hive.init(dir.path);
      box = await Hive.openBox<String>('ai_zongce_test');
    });

    setUp(() => store = ZcStore(box, dir.path));

    /// 两个自动源一律 stub 成 null（引擎回退手动值），免得测试里去碰真成绩/真志愿。
    ProviderContainer withMats(List<ZcMaterial> mats) => ProviderContainer(
      overrides: [
        zcStoreProvider.overrideWith((ref) async => store),
        zcMaterialsProvider.overrideWith((ref) async => mats),
        zcAutoWeightProvider.overrideWith((ref, year) async => null),
        zcAutoVolunteerProvider.overrideWith((ref, year) async => null),
      ],
    );

    List<ZcMaterial> sampleMats() => [
      // 德育 · 优秀事迹：单选就高 → 只有 5 分那条计入
      ZcMaterial(
        id: 'd1',
        typeId: ZcTypeId.deed,
        name: '三支一扶',
        dateIso: '2026-05-01',
        level: 0,
      ),
      ZcMaterial(
        id: 'd2',
        typeId: ZcTypeId.deed,
        name: '校级表扬信',
        dateIso: '2026-05-01',
        level: 2,
      ),
      // 智育 · 学科竞赛：最高项 > 5 → 只计最高那一项
      ZcMaterial(
        id: 'c1',
        typeId: ZcTypeId.contest,
        name: '蓝桥杯',
        dateIso: '2026-05-01',
        cat: 'c1',
        level: 0,
        opt: 0,
      ),
      ZcMaterial(
        id: 'c2',
        typeId: ZcTypeId.contest,
        name: '数学建模',
        dateIso: '2026-05-01',
        cat: 'c2',
        level: 0,
        opt: 0,
      ),
      // 体育：没有「计入 / 未计入」这层取舍
      ZcMaterial(
        id: 't1',
        typeId: ZcTypeId.sportComp,
        name: '校运会 100m',
        dateIso: '2026-05-01',
        level: 2,
        opt: 0,
      ),
    ];

    test('概览：总评 + 五育 + 等次 + 材料按育统计', () async {
      final container = withMats(sampleMats());
      addTearDown(container.dispose);

      final r = await const GetZongceTool().run(contextWith(container), {});
      expect(r.ok, isTrue);
      expect(r.content, contains('综测（测评学年 2026'));
      expect(r.content, contains('总评成绩'));
      for (final yu in const ['· 德育 ', '· 智育 ', '· 体育 ', '· 美育 ', '· 劳育 ']) {
        expect(r.content, contains(yu));
      }
      expect(r.content, contains('加分材料 5 条：德育 2 · 智育 2 · 体育 1。'));
      expect(r.ui?['kind'], 'zongce');
      expect(r.ui?['year'], 2026);
    });

    test('★ detail=true：逐条给出板块与「计入 / 未计入」（德育按表 3~7、智育竞赛按封顶 5 分）', () async {
      final container = withMats(sampleMats());
      addTearDown(container.dispose);

      final r = await const GetZongceTool().run(contextWith(container), {
        'detail': true,
      });
      final lines = r.content.split('\n');
      String lineOf(String needle) =>
          lines.firstWhere((l) => l.contains(needle), orElse: () => '');

      expect(lineOf('三支一扶'), contains('[德育 · 优秀事迹]'));
      expect(lineOf('三支一扶'), contains('+5（计入）'));
      expect(lineOf('校级表扬信'), contains('+3（未计入）'));
      expect(lineOf('蓝桥杯'), contains('[智育 · 学科技能竞赛]'));
      expect(lineOf('蓝桥杯'), contains('+20（计入）'));
      expect(lineOf('数学建模'), contains('+12（未计入）'));
      expect(
        lineOf('校运会'),
        isNot(contains('计入')),
        reason: '体育 / 美育 / 劳育没有这层取舍，只给分值',
      );
      // 口径说明要带上，免得模型自己编一套「为什么没计入」
      expect(r.content, contains('德育按表 3~7 各板块口径'));
    });

    test('默认不给逐条明细（省 token）', () async {
      final container = withMats(sampleMats());
      addTearDown(container.dispose);

      final r = await const GetZongceTool().run(contextWith(container), {});
      expect(r.content, contains('加分材料 5 条'));
      expect(
        r.content.contains('[德育 · 优秀事迹]'),
        isFalse,
        reason: '逐条明细只在 detail=true 时给',
      );
    });

    test('材料库为空时说明是「没有材料」，不是「考了 0 分」', () async {
      final container = withMats(const []);
      addTearDown(container.dispose);

      final r = await const GetZongceTool().run(contextWith(container), {});
      expect(r.ok, isTrue);
      expect(r.content, contains('还没有任何加分材料'));
    });

    test('year 参数决定读哪一学年的手动项', () async {
      await store.saveManual(2025, const ZcManual(deyuPingyi: 20));
      final container = withMats(const []);
      addTearDown(container.dispose);

      final r = await const GetZongceTool().run(contextWith(container), {
        'year': 2025,
      });
      expect(r.content, contains('测评学年 2025'));
      expect(
        r.content,
        contains('· 德育 80'),
        reason: '基础 60 + 民主评议 20（该学年手动项）',
      );
    });
  });
}
