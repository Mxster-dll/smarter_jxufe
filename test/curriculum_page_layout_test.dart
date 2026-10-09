// 培养方案页（Fluent 改写后）的**纯渲染**冒烟守卫（2026-10-09 立）。
//
// 这一页本轮从「自研半成品表格（16 列 × N 行横向滚动）」改成「指标卡 + 工具条 +
// 分组清单 + 实践环节」，所以补这条冒烟，只测「画得出来、不溢出、降级文案对」，
// 不碰像素与配色（那是 golden 的事）。数据全**合成**，不掺真实学籍 / 课表。
//
// 覆盖点：
// 1. 三种分组形态（按分类 / 按开课学期 / 平铺）都能画；
// 2. 搜索真的筛（命中计数 + 只剩命中的课）；
// 3. 实践环节那一段（含「没取到」与「筛空」两种降级）；
// 4. 开课学期拿不到时的如实提示；
// 5. 窄屏 360 / 280 不许溢出（本轮实测最容易出事的地方：行尾学分 + 徽标 + 星标）；
// 6. 点开课程行看学时明细。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/course/data/models/assessment_method.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_nature.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_requirement.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/credit_hour.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_screen.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_state.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_viewmodel.dart';

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
    total: 64,
    lecture: 48,
    lab: 16,
    practice: 0,
    other: 0,
    weekly: 4,
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
  ),
];

const _semesters = [
  '2025-2026学年第一学期',
  '2025-2026学年第一学期',
  '2025-2026学年第二学期',
  '',
];

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
      code: '1314300014',
      name: '毕业实习',
      credit: 4,
      category: '实习实训',
      assessment: '考查',
      weeks: 4,
    ),
  ],
);

CurriculumState _state({
  List<Course>? courses,
  List<String> semesters = _semesters,
  PracticeCurriculum? practice = _practice,
  String? errorMessage,
  String? semestersError,
  String? practiceError,
  bool isLoadingTable = false,
}) => CurriculumState(
  selectedYear: 2025,
  years: const [2025, 2024],
  curriculum: courses == null
      ? null
      : Curriculum(
          year: 2025,
          collegeName: '计算机与人工智能学院',
          majorName: '计算机科学与技术',
          courses: courses,
        ),
  semesters: semesters,
  practice: practice,
  errorMessage: errorMessage,
  semestersError: semestersError,
  practiceError: practiceError,
  isLoadingTable: isLoadingTable,
);

/// 假 ViewModel：只回一份固定 state，`reload` 不动（页面自动刷新会调它）。
///
/// ⚠ 必须重写 `reload` —— 真实现会去碰 `late final` 的仓库字段，
/// 测试里没装配依赖，会抛 `LateInitializationError`。
class _FakeViewModel extends CurriculumViewModel {
  _FakeViewModel(this.initial);

  final CurriculumState initial;

  @override
  Future<CurriculumState> build() async => initial;

  @override
  Future<void> reload({bool force = false}) async {}
}

Future<void> _pump(
  WidgetTester tester,
  double width,
  double height, {
  CurriculumState? state,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        curriculumViewModelProvider.overrideWith(
          () => _FakeViewModel(state ?? _state(courses: _courses)),
        ),
      ],
      child: MaterialApp(
        // ⚠ 测试环境跑在 `TargetPlatform.android` + M3 下，水波纹默认要
        // `shaders/ink_sparkle.frag` 这个 asset（测试包里有概率取不到 →
        // 抛 `Asset 'shaders/ink_sparkle.frag' not found` 把用例打红）。
        // 这里显式换回 `InkRipple`：点击反馈与真实一致，且不吃着色器。
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const Scaffold(body: CurriculumScreen(showAppBar: false)),
      ),
    ),
  );
  // ⚠ 有转圈动画的场合（`isLoadingTable`）不能 pumpAndSettle —— 永远等不到静止。
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    320,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('宽窗口：指标卡 / 分组清单 / 实践环节 / 脚注都画得出来', (tester) async {
    await _pump(tester, 1200, 900);
    // 指标卡
    expect(find.text('理论课程（教学计划）'), findsOneWidget);
    expect(find.text('实践环节'), findsOneWidget);
    expect(find.textContaining('共 4 门'), findsWidgets);
    // 分组清单：大类节标题 + 二级分类组头 + 课程行 + 行尾学分与徽标
    expect(find.text('2024公共课'), findsOneWidget);
    expect(find.text('2024专业教育课'), findsOneWidget);
    expect(find.text('公共外语课'), findsOneWidget);
    expect(find.text('高等数学A'), findsOneWidget);
    expect(find.text('4 学分'), findsWidgets);
    expect(find.text('必修'), findsWidgets);
    expect(find.text('选修'), findsWidgets);
    // 行内描述：代码 + 考核方式（「按分类」时二级分类由组头承担，不重复）
    expect(find.textContaining('[1000000001] · 考试'), findsOneWidget);
    // 工具条的计数行
    expect(find.text('共 4 门 · 12 学分'), findsOneWidget);
    // 实践环节那一段
    await _scrollTo(tester, find.text('军事训练'));
    expect(find.text('毕业实习'), findsOneWidget);
    expect(find.textContaining('2025-2026 学年第一学期'), findsWidgets);
    // 脚注
    await _scrollTo(tester, find.textContaining('数据来源：教务'));
    expect(find.textContaining('数据来源：教务'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('★ 搜索真的筛：只剩命中的课，计数行给「命中 N 门」', (tester) async {
    await _pump(tester, 1200, 900);
    await tester.enterText(find.byType(TextField), '英语');
    await tester.pumpAndSettle();

    expect(find.text('大学英语I'), findsOneWidget);
    expect(find.text('六级英语专题'), findsOneWidget);
    expect(find.text('高等数学A'), findsNothing);
    expect(find.text('命中 2 门 · 4 学分（共 4 门 · 12 学分）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜不到：如实说「没有匹配」，而不是假装没有课', (tester) async {
    await _pump(tester, 1200, 900);
    await tester.enterText(find.byType(TextField), '量子力学');
    await tester.pumpAndSettle();
    expect(find.textContaining('没有匹配「量子力学」的课程（共 4 门）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('★ 切「按开课学期」：节标题换成学期（含短码），未排定的排最后', (tester) async {
    await _pump(tester, 1200, 900);
    await tester.tap(find.text('按开课学期'));
    await tester.pumpAndSettle();

    expect(find.text('2025-2026 学年第一学期'), findsWidgets);
    expect(find.textContaining('· 251'), findsWidgets);
    await _scrollTo(tester, find.text('开课学期未排定'));
    expect(find.text('开课学期未排定'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切「平铺」：只有一节「全部课程」', (tester) async {
    await _pump(tester, 1200, 900);
    await tester.tap(find.text('平铺'));
    await tester.pumpAndSettle();
    expect(find.text('全部课程'), findsOneWidget);
    expect(find.text('2024公共课'), findsNothing, reason: '平铺不再画大类节标题');
    // 平铺时组头没了，行内要把二级分类带出来（「按分类」时组头已经写了，不重复）
    expect(find.textContaining('[1000000001] · 公共数学课 · 考试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('快筛「主干课程」：只剩主干课（行首星标）', (tester) async {
    await _pump(tester, 1200, 900);
    await tester.tap(find.text('主干课程'));
    await tester.pumpAndSettle();
    expect(find.text('高等数学A'), findsOneWidget);
    expect(find.text('大学英语I'), findsNothing);
    expect(find.byIcon(Icons.star_rate_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('★ 点课程行展开学时明细（总学时 / 讲授 / 实验 / 周学时）', (tester) async {
    await _pump(tester, 1200, 900);
    await tester.tap(find.text('高等数学A'));
    await tester.pumpAndSettle();
    expect(find.text('总学时'), findsOneWidget);
    expect(find.text('64'), findsOneWidget);
    expect(find.text('讲授'), findsOneWidget);
    expect(find.text('实验'), findsOneWidget);
    expect(find.text('周学时'), findsOneWidget);
    expect(find.text('课程地位'), findsOneWidget);
    // 再点一次收起
    await tester.tap(find.text('高等数学A'));
    await tester.pumpAndSettle();
    expect(find.text('总学时'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('★ 开课学期没取到：只在「按开课学期」时如实提示，课程照常显示', (tester) async {
    await _pump(
      tester,
      1200,
      900,
      state: _state(courses: _courses, semesters: const [], semestersError: '没有教务会话'),
    );
    // 默认（按分类）不吵这件事
    expect(find.textContaining('开课学期没取到'), findsNothing);
    await tester.tap(find.text('按开课学期'));
    await tester.pumpAndSettle();
    expect(find.textContaining('开课学期没取到'), findsOneWidget);
    expect(find.text('高等数学A'), findsWidgets, reason: '课程本身照常显示');
    expect(tester.takeException(), isNull);
  });

  testWidgets('教务的「学年学期」列全空：说清是「没排定」而不是「没取到」', (tester) async {
    await _pump(
      tester,
      1200,
      900,
      state: _state(courses: _courses, semesters: const ['', '', '', '']),
    );
    await tester.tap(find.text('按开课学期'));
    await tester.pumpAndSettle();
    expect(find.textContaining('「学年学期」列是空的'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('★ 实践环节没取到：只影响那一段，理论课程照常', (tester) async {
    await _pump(
      tester,
      1200,
      900,
      state: _state(
        courses: _courses,
        practice: null,
        practiceError: '获取JSESSIONID失败：没有教务会话',
      ),
    );
    expect(find.text('高等数学A'), findsOneWidget);
    await _scrollTo(tester, find.textContaining('实践环节表没取到'));
    expect(find.textContaining('实践环节表没取到'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('理论课程表空：如实说「没有课程条目」', (tester) async {
    await _pump(tester, 1200, 900, state: _state(courses: const []));
    expect(find.textContaining('没有课程条目'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('还没选专业：提示先选范围（不画空壳）', (tester) async {
    await _pump(tester, 1200, 900, state: _state());
    expect(find.textContaining('先在上面选好年级'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('正在取表：显示加载文案（不用裸转圈）', (tester) async {
    await _pump(
      tester,
      1200,
      900,
      state: _state(isLoadingTable: true),
      settle: false,
    );
    expect(find.text('正在从教务读取培养方案…'), findsOneWidget);
  });

  testWidgets('取数失败：顶部一条错误 InfoBar + 重试', (tester) async {
    await _pump(
      tester,
      1200,
      900,
      state: _state(courses: _courses, errorMessage: '凭证已失效，请重新登录!'),
    );
    expect(find.text('取数失败'), findsOneWidget);
    expect(find.textContaining('凭证已失效'), findsWidgets);
    expect(find.text('重试'), findsWidgets);
    expect(find.text('高等数学A'), findsOneWidget, reason: '有内容就照常显示');
    expect(tester.takeException(), isNull);
  });

  testWidgets('★ 窄屏 360×800 不许溢出', (tester) async {
    await _pump(tester, 360, 800);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('★ 极窄 280×640：展开学时明细后也不许溢出', (tester) async {
    await _pump(tester, 280, 640);
    expect(tester.takeException(), isNull);
    await _scrollTo(tester, find.text('高等数学A'));
    await tester.tap(find.text('高等数学A'));
    await tester.pumpAndSettle();
    expect(find.text('总学时'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
