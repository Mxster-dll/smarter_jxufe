import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/graduation_requirement.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/presentation/graduation_requirements_screen.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_calendar_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

/// 一批工具（培养方案 / 毕业学分 / 志愿 / 综测 / 材料 / 校历）的取数与文案。
///
/// 全部靠 override 底层 provider 来测 —— 这样不碰 Hive、不碰网络，
/// 测的就是**工具自己的聚合与措辞**。

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
  CourseRequirement requirement = CourseRequirement.compulsory,
}) => Course(
  code: code,
  name: name,
  credit: credit,
  creditHour: const CreditHour(total: 64, lecture: 64, weekly: 4),
  mainCategory: mainCategory,
  subCategory: '',
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
    ProviderContainer withReqs(List<GraduationRequirement> rows) =>
        ProviderContainer(
          overrides: [
            graduationRequirementsProvider.overrideWith((ref) async => rows),
          ],
        );

    test('有「合计」行时标出来', () async {
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
      expect(r.content, contains('通识必修课：40 学分'));
      expect(r.content, contains('合计：100 学分（合计行）'));
    });

    test('没有「合计」行时把各分项相加并说明这是自己加的', () async {
      final container = withReqs(const [
        GraduationRequirement(index: 1, item: '通识必修课', credit: 40.5),
        GraduationRequirement(index: 2, item: '专业必修课', credit: 60),
      ]);
      addTearDown(container.dispose);

      final r = await const GetGraduationCreditsTool().run(
        contextWith(container),
        {},
      );
      expect(r.content, contains('各分项相加 = 100.5 学分'));
    });

    test('取不到时提示要教务会话', () async {
      final container = ProviderContainer(
        overrides: [
          graduationRequirementsProvider.overrideWith(
            (ref) async => throw Exception('JSESSIONID 为空'),
          ),
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
}
