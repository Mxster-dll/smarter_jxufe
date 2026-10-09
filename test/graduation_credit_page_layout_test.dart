import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/fluent/fluent.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/providers/credit_progress_provider.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/credit_progress.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/general_education_catalog.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/presentation/graduation_requirements_screen.dart';

/// 毕业学分页的**纯渲染**冒烟守卫（2026-10-08 立）。
///
/// 为什么破例给这一页加 widget 测试：§13.2 记的「⑤ 不加 fixture / widget 测试」是
/// 2026-09-11 Fluent 改写那轮的范围决定；这一轮页面从「一张只读表」变成
/// 「指标卡 + 可展开待修清单 + 逐项进度条 + 未归类卡」，**这条冒烟当场抓出两个真溢出**
/// （`CompulsoryProgressCard` 的两处 `Row` + `Spacer` 在 360 / 280 宽分别溢出 50 / 130px）。
/// 只测「画得出来、不溢出、降级文案对」，不测像素与配色（那是 golden 的事）。
///
/// 数据全是**合成**的（不掺任何真实学籍 / 成绩）。
GraduationCreditReport _report({
  bool requirementsError = false,
  bool withFailed = false,
}) =>
    GraduationCreditReport(
      requirementsError: requirementsError ? 'Exception: 凭证已失效，请重新登录!' : null,
      progress: GraduationCreditProgress(
        compulsory: CompulsoryCreditProgress(
          required: 113,
          earned: 56,
          courses: [
            for (var i = 0; i < 50; i++)
              CompulsoryCourseState(
                code: '10000000$i',
                name: '必修课名称$i',
                credit: i < 25 ? 2 : 3,
                earned: i < 25 ? 2 : 0,
                category: i.isEven ? '学科基础课' : '公共外语课',
                // 挂科样例：**考核过**（成绩单上有）但一分没拿到
                attempted: withFailed && i == 49,
                score: withFailed && i == 49 ? 52 : null,
              ),
          ],
        ),
        electives: const [
          CreditProgressItem(
            title: '2024公共外语选修课',
            required: 2,
            earned: 0,
            courses: [],
            rule: '培养方案「公共外语课」（选修）',
            poolCount: 11,
            poolCredits: 22,
          ),
          CreditProgressItem(
            title: '2024美育选修2学分',
            required: 2,
            earned: 2,
            courses: [
              CreditProgressCourse(
                code: '1004809771',
                name: '工艺美术简史',
                credit: 1.5,
                earned: 2,
              ),
            ],
            rule: '通识课程库「美育」模块',
          ),
          CreditProgressItem(
            title: '2024科学、技术与方法选修2学分',
            required: 2,
            // 故意超额：验「已超出 X 学分（不抵扣其它项）」那行
            earned: 3,
            courses: [
              CreditProgressCourse(
                code: '1001',
                name: '人工智能导论',
                credit: 1.5,
                earned: 1.5,
              ),
              CreditProgressCourse(
                code: '1002',
                name: '数据科学导论',
                credit: 1.5,
                earned: 1.5,
              ),
            ],
            rule: '通识课程库「科学、技术与方法」模块',
          ),
          CreditProgressItem(
            title: '2024历史、政治与社会选修2学分',
            required: 2,
            earned: 0,
            courses: [],
            rule: '通识课程库「历史、政治与社会（经典阅读）」模块',
          ),
          CreditProgressItem(
            title: '2024哲学、思维与语言选修2学分',
            required: 2,
            earned: 0,
            courses: [],
            rule: '通识课程库「哲学、思维与语言」模块',
          ),
          CreditProgressItem(
            title: '2024学科开放选修课',
            required: 3,
            earned: 0,
            courses: [],
            rule: '培养方案「学科开放课」（选修）',
            poolCount: 3,
            poolCredits: 9,
          ),
          CreditProgressItem(
            title: '2024专业方向选修课',
            required: 15,
            earned: 8,
            courses: [
              CreditProgressCourse(
                code: '1014300422',
                name: 'Linux操作系统',
                credit: 2,
                earned: 2,
              ),
              CreditProgressCourse(
                code: '1004703083',
                name: '数学建模',
                credit: 3,
                earned: 3,
              ),
              CreditProgressCourse(
                code: '1004701363',
                name: '计量经济学',
                credit: 3,
                earned: 3,
              ),
            ],
            rule: '培养方案「专业方向课」（选修）',
            poolCount: 29,
            poolCredits: 71,
          ),
          CreditProgressItem(
            title: '2024神秘选修课',
            required: 6,
            earned: 0,
            courses: [],
            rule: '教务要求表（本项口径未识别，只显示要求学分）',
            recognized: false,
          ),
        ],
        unmatched: const [
          UnmatchedCourse(
            course: CreditProgressCourse(
              code: '1003000011',
              name: '大学生安全教育',
              credit: 1,
              earned: 1,
            ),
            reason: '既不在本专业培养方案、也不在通识课程库里',
          ),
          UnmatchedCourse(
            course: CreditProgressCourse(
              code: '',
              name: '一门名字特别特别长的未归类课程用来试探换行表现',
              credit: 2,
              earned: 2,
            ),
            reason: '通识课程库把它归到「发展指导课」模块，教务要求表里没有这一项',
          ),
        ],
        earnedTotal: 59,
        practice: const PracticeCreditProgress(
          required: 18,
          earned: 2,
          label: '2025 · 示例学院 · 示例专业',
          stages: [
            PracticeStageState(
              code: '1305002302',
              name: '军事训练',
              category: '军训',
              credit: 2,
              earned: 2,
              semester: '2025-2026学年第一学期',
            ),
            PracticeStageState(
              code: '1302600064',
              name: '创新创业实践活动',
              category: '科研创新实践',
              credit: 4,
              earned: 0,
            ),
            PracticeStageState(
              code: '1314300014',
              name: '毕业实习',
              category: '实习实训',
              credit: 4,
              earned: 0,
            ),
            PracticeStageState(
              code: '1314300058',
              name: '毕业设计',
              category: '论文设计',
              credit: 8,
              earned: 0,
            ),
          ],
        ),
        curriculumLabel: '2025 · 示例学院 · 示例专业',
        catalogScope: const GeneralEducationScope(
          sheets: [],
          cohort: 2025,
          exactCohortMatch: false,
        ),
        notes: const ['测试口径一', '测试口径二'],
      ),
    );

/// 页面挂的 `PageAutoRefresher` 首帧就会 `ref.read` 要求表 provider
/// （`invalidateIfLoaded`）—— 不 override 它会一路摸到 `imsAuthRepository` → Hive。
Future<void> _pump(
  WidgetTester tester,
  double width,
  double height, {
  GraduationCreditReport? report,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        graduationRequirementsProvider.overrideWith((ref) async => const []),
        graduationCreditReportProvider.overrideWith(
          (ref) async => report ?? _report(),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: GraduationRequirementsScreen(showAppBar: false)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 页内滚动到某个件可见为止（页面会越来越长，别再靠固定视口假设）。
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    320,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('桌面宽窗口：各节都画得出来，滚到底也不抛', (tester) async {
    await _pump(tester, 1600, 1000);
    // 顶部三张指标卡
    expect(find.text('必修课'), findsOneWidget);
    expect(find.text('选修课'), findsOneWidget);
    expect(find.text('实践环节'), findsOneWidget);
    // 节顺序 = 必修课进度 → 实践环节进度 → 选修课进度 → 未归类（页面变长了，逐节滚过去看）
    expect(find.text('必修课进度'), findsOneWidget);
    await _scrollTo(tester, find.text('实践环节进度'));
    expect(find.text('实践环节进度'), findsOneWidget);
    // 实践环节四项直列（军训已修、其余未修）
    await _scrollTo(tester, find.text('军事训练'));
    expect(find.text('毕业设计'), findsOneWidget);
    await _scrollTo(tester, find.text('选修课进度'));
    expect(find.text('选修课进度'), findsOneWidget);
    // 认不出的要求项要明说「只显示要求学分」，不假装算过
    await _scrollTo(tester, find.textContaining('本项口径未识别'));
    expect(find.textContaining('本项口径未识别'), findsOneWidget);
    // 超额那行
    await _scrollTo(tester, find.textContaining('已超出 1 学分'));
    expect(find.textContaining('已超出 1 学分'), findsOneWidget);
    // ListView 懒构建，底部的未归类区要先滚下去才进树
    await _scrollTo(tester, find.text('未归类课程（2 门）'));
    expect(find.text('未归类课程（2 门）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('★ 窄屏 360×800：不许溢出', (tester) async {
    await _pump(tester, 360, 800);
    expect(tester.takeException(), isNull);
  });

  testWidgets('★ 极窄 280×640：不许溢出（旧版此处溢出 130px）', (tester) async {
    await _pump(tester, 280, 640);
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开「查看还差 N 门」后滚到最底：不许溢出 / 抛异常', (tester) async {
    await _pump(tester, 360, 720);
    final toggle = find.textContaining('查看还差');
    await _scrollTo(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('必修课名称30'));
    expect(find.text('必修课名称30'), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('教务要求表挂了：只有选修那一节报错，必修 / 实践环节 / 未归类照常显示', (tester) async {
    await _pump(tester, 1200, 900, report: _report(requirementsError: true));
    expect(find.text('必修课进度'), findsOneWidget);
    expect(find.text('实践环节进度'), findsOneWidget);
    await _scrollTo(tester, find.text('教务「毕业学分要求」表读取失败'));
    expect(find.text('教务「毕业学分要求」表读取失败'), findsOneWidget);
    await _scrollTo(tester, find.text('未归类课程（2 门）'));
    expect(find.text('未归类课程（2 门）'), findsOneWidget);
  });

  testWidgets('培养方案拿不到：必修 / 实践环节都说「拿不到」，选修段说「未返回」', (tester) async {
    await _pump(
      tester,
      1200,
      900,
      report: const GraduationCreditReport(
        progress: GraduationCreditProgress.empty,
      ),
    );
    expect(find.textContaining('拿不到本专业培养方案'), findsWidgets);
    await _scrollTo(tester, find.text('教务未返回毕业学分要求数据，可稍后重试。'));
    expect(find.text('教务未返回毕业学分要求数据，可稍后重试。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('挂科（2026-10-08 加）', () {
    testWidgets('★ 有挂科时警示条顶在最上面，且点名课程与分数', (tester) async {
      await _pump(tester, 1200, 900, report: _report(withFailed: true));
      // 警示条必须在**指标卡上面**：第一屏就该看见
      final bar = find.byKey(const Key('recFailedBar'));
      expect(bar, findsNothing, reason: '推免页那个 key 不该长在毕业学分页上');
      expect(find.text('有 1 门挂科，未获得学分'), findsOneWidget);
      expect(find.textContaining('必须重修通过才计入毕业学分'), findsOneWidget);
      // 明细行：课程名 + 分数
      expect(find.text('必修课名称49'), findsOneWidget);
      expect(find.text('52 分'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('没挂科时整条不画（不许常驻一条空警示）', (tester) async {
      await _pump(tester, 1200, 900);
      expect(find.textContaining('门挂科，未获得学分'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('★ 窄屏也不许溢出（警示条含长文案 + 明细行）', (tester) async {
      for (final (w, h) in [(360.0, 800.0), (280.0, 640.0)]) {
        await _pump(tester, w, h, report: _report(withFailed: true));
        expect(tester.takeException(), isNull, reason: '${w.toInt()} 宽');
      }
    });
  });

  group('顶部指标卡等高（用户 2026-10-08 要求）', () {
    // ⚠ 页面内容被 `FluentPageBackground.maxContentWidth = 880` 夹住（Fluent 口径：
    // 宽窗口不把内容拉到 4K 全宽），于是 `_ReportView` 的 LayoutBuilder 实际只拿到
    // **832** —— `Breakpoints.extraWide`(1000) 在**本页永远到不了**，真实桌面布局是
    // 「必修 + 选修同行、实践环节另起一行」。这条约束是 2026-10-08 实测出来的
    // （探针打印 `overview=Size(832.0, 230.0)`），别再按 1600 窗口去假设三卡同行。
    testWidgets('★ 真实页面上：同排的必修 / 选修必须等高', (tester) async {
      await _pump(tester, 1600, 1000);
      final cards = find.byType(FluentMetricCard);
      expect(cards, findsNWidgets(3));
      final h0 = tester.getSize(cards.at(0)).height;
      final h1 = tester.getSize(cards.at(1)).height;
      expect(h0, closeTo(h1, 0.01), reason: '必修 vs 选修：$h0 / $h1');
      // 实践环节是**另一排**（全宽），本来就与上面两张不等高
      expect(tester.getSize(cards.at(2)).width, greaterThan(h0 * 2));
    });

    testWidgets('★ 更宽的窗口也一样（布局只有两档，见 credit_progress_widgets 注释）', (tester) async {
      await _pump(tester, 2400, 1000);
      final cards = find.byType(FluentMetricCard);
      final h0 = tester.getSize(cards.at(0)).height;
      final h1 = tester.getSize(cards.at(1)).height;
      expect(h0, closeTo(h1, 0.01), reason: '必修 vs 选修：$h0 / $h1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('窄屏堆叠时不强制等高（本来就一列）', (tester) async {
      await _pump(tester, 360, 800);
      expect(tester.takeException(), isNull);
    });
  });
}
