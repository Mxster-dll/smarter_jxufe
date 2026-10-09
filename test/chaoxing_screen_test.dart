/// 学习通**界面**渲染守卫（数据层另有 `chaoxing_data_test.dart`）。
///
/// 为什么要有这一层：数据链路的守卫再多，也拦不住「页面里 provider 读错 / 段标题拼错 /
/// 空态没兜住」。这里用**假控制器**（`ChaoxingController` 子类，只覆盖 `build` 与四个动作）
/// 喂一份固定快照，钉住主页四个区块、三个二级页的筛选与弹层、以及空数据不崩。
///
/// ⚠ 这里**不碰网络与 Hive**：控制器被整体替换，`chaoxingRepositoryProvider` 根本不会被读。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/features/chaoxing/data/providers/chaoxing_providers.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_course.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_notice.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_sign.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_snapshot.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_common.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_courses_screen.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_notices_screen.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_screen.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_signs_screen.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_works_screen.dart';

/// 假控制器：`build` 直接给快照，四个动作只记账（**不碰仓库 / 网络 / Hive**）。
class _FakeController extends ChaoxingController {
  _FakeController(this.snapshot);

  ChaoxingSnapshot snapshot;
  int refreshes = 0;
  int noticeRefreshes = 0;
  int clears = 0;

  /// 手动刷新（force: true）的次数 —— 自动刷新不计入。
  int forcedRefreshes = 0;

  /// 签到：点开某条时「查询我的状态」的次数（1 请求/活动）。
  int signDetailCalls = 0;

  /// 签到：手动全量更新的次数与档位（false = 只本学期，true = 含往期）。
  int signFullCalls = 0;
  bool? signFullAllCourses;

  @override
  Future<bool> loadSignDetail(ChaoxingSign sign) async {
    signDetailCalls++;
    snapshot = snapshot.copyWith(
      signs: [
        for (final s in snapshot.signs)
          if (s.key == sign.key)
            s.copyWith(status: ChaoxingSignStatus.signed, statusLoaded: true)
          else
            s,
      ],
    );
    return true;
  }

  @override
  Future<void> refreshSignsFull({bool allCourses = false}) async {
    signFullCalls++;
    signFullAllCourses = allCourses;
  }

  @override
  Future<ChaoxingSnapshot> build() async => snapshot;

  @override
  Future<void> refresh({bool force = false}) async {
    refreshes++;
    if (force) forcedRefreshes++;
  }

  @override
  Future<void> refreshNoticesOnly() async {
    noticeRefreshes++;
  }

  @override
  Future<void> clear() async {
    clears++;
    snapshot = ChaoxingSnapshot.empty;
  }
}

const _course = ChaoxingCourse(
  courseId: '100000002',
  classId: '200000002',
  cpi: '900000001',
  name: '261学期 线性代数(工)',
);

ChaoxingSnapshot _snapshot() => ChaoxingSnapshot(
  courses: const [_course],
  works: [
    ChaoxingWork(
      workId: 'w1',
      title: '第一章 行列式',
      courseId: _course.courseId,
      courseName: _course.name,
      dueAt: DateTime(2026, 9, 20, 23, 59),
      status: ChaoxingWorkStatus.todo,
    ),
    ChaoxingWork(
      workId: 'w2',
      title: '第二章 矩阵',
      courseId: _course.courseId,
      courseName: _course.name,
      dueAt: DateTime(2026, 9, 10, 23, 59),
      status: ChaoxingWorkStatus.done,
      score: 90,
    ),
    ChaoxingWork(
      workId: 'w3',
      title: '第三章 向量组',
      courseId: _course.courseId,
      courseName: _course.name,
      status: ChaoxingWorkStatus.pendingReview,
    ),
  ],
  notices: [
    ChaoxingNotice(
      id: 'n1',
      title: '关于期中考试安排的通知',
      content: '期中考试定于第 8 周进行，具体考场另行通知。',
      sender: '教务处',
      sentAt: DateTime(2026, 9, 19, 9, 0),
    ),
    ChaoxingNotice(
      id: 'n2',
      title: '作业提醒',
      content: '你有一份作业即将截止。',
      sender: '线性代数(工)',
      sentAt: DateTime(2026, 9, 18, 9, 0),
      read: true,
      top: true,
      sourceTag: 'courseId${_course.courseId}',
      courseId: _course.courseId,
    ),
  ],
  fetchedAt: DateTime(2026, 9, 19, 20, 30),
);

Widget _app(Widget home, ChaoxingController controller) => ProviderScope(
  overrides: [chaoxingControllerProvider.overrideWith(() => controller)],
  child: MaterialApp(navigatorObservers: [appRouteObserver], home: home),
);

/// **只在弹窗里**找文案：列表行与弹窗经常同文案（标题、状态、课程名都会重复）。
Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

void main() {
  group('★ 通知里的作业提醒（用户 2026-09-20 选定的 B 方案）', () {
    /// 一节课 + 两条平台自动发的作业通知：一条**已被作业列表覆盖**（标题包含），
    /// 一条**没扫到**（这才是要显示出来的）。
    ChaoxingSnapshot withHints() => ChaoxingSnapshot(
      courses: const [_course],
      works: [
        ChaoxingWork(
          workId: 'w1',
          title: '第一章 行列式',
          courseId: _course.courseId,
          courseName: _course.name,
          dueAt: DateTime(2026, 9, 20, 23, 59),
          status: ChaoxingWorkStatus.todo,
        ),
      ],
      notices: [
        ChaoxingNotice(
          id: 'dup',
          title: '作业:《261学期 线性代数（工）》第一章 行列式',
          content: '已发布',
          sender: '某老师',
          courseId: _course.courseId,
          sourceTag: 'courseId${_course.courseId}',
          sentAt: DateTime(2026, 9, 17, 9),
        ),
        ChaoxingNotice(
          id: 'gap',
          title: '作业:《261学期 线性代数（工）》第二章 矩阵',
          content: '已发布，请在截止时间前提交。',
          sender: '某老师',
          courseId: _course.courseId,
          sourceTag: 'courseId${_course.courseId}',
          sentAt: DateTime(2026, 9, 18, 9),
        ),
        ChaoxingNotice(
          id: 'ended',
          title: '作业结束提醒',
          content: '作业已结束',
          sender: '某老师',
          courseId: _course.courseId,
          sentAt: DateTime(2026, 9, 16, 9),
        ),
      ],
      fetchedAt: DateTime(2026, 9, 20, 8),
    );

    Finder hintCard() => find.ancestor(
      of: find.text('通知里的作业提醒'),
      matching: find.byType(ChaoxingSectionCard),
    );

    testWidgets('只显示「没扫到」的那条，点开是通知详情', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);

      final controller = _FakeController(withHints());
      await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
      await tester.pumpAndSettle();

      expect(find.text('通知里的作业提醒'), findsOneWidget);
      expect(
        find.descendant(of: hintCard(), matching: find.byType(ChaoxingNoticeRow)),
        findsOneWidget,
        reason: '已扫到的那条（标题里含作业标题）与「作业结束提醒」都不该进来',
      );
      expect(
        find.descendant(of: hintCard(), matching: find.textContaining('第二章 矩阵')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hintCard(), matching: find.textContaining('第一章 行列式')),
        findsNothing,
      );

      await tester.tap(find.descendant(of: hintCard(), matching: find.byType(ChaoxingNoticeRow)));
      await tester.pumpAndSettle();
      expect(_inDialog('作业:《261学期 线性代数（工）》第二章 矩阵'), findsOneWidget);
      expect(_inDialog('已发布，请在截止时间前提交。'), findsOneWidget);
    });

    testWidgets('没有「没扫到」的作业通知时整块不画（不留空卡片）', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);

      final controller = _FakeController(_snapshot());
      await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
      await tester.pumpAndSettle();

      expect(find.text('通知里的作业提醒'), findsNothing,
          reason: '默认快照里那条「作业提醒」不是 `作业:` 开头，不该被当成发布类通知');
    });

    testWidgets('非当下学期的课：课程页挂「未扫描」备注，而不是「这门课没有作业记录」',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);

      final controller = _FakeController(
        ChaoxingSnapshot(
          courses: const [_course],
          works: const [],
          notices: const [],
          skippedCourseKeys: [_course.key],
          fetchedAt: DateTime(2026, 9, 20, 8),
        ),
      );
      await tester.pumpWidget(_app(const ChaoxingCoursesScreen(), controller));
      await tester.pumpAndSettle();

      expect(find.text('非当下学期，未扫描（只扫当下学期）'), findsOneWidget);
      expect(find.text('这门课没有作业记录'), findsNothing);
    });
  });

  group('主页', () {
    testWidgets('四个区块都渲染，概览三个数与角标口径一致', (tester) async {
      // 主页是长滚动页：默认 800×600 视口下第四个区块根本不会被 build
      // （ListView 惰性构建），所以先把视口放大再断言。
      // ⚠ `physicalSize` 是**物理像素**，测试默认 dpr = 3 → 必须同时把 dpr 设成 1，
      // 否则 1000×2400 实际只有 333×800 逻辑像素（比默认还窄）。
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);

      final controller = _FakeController(_snapshot());
      await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
      await tester.pumpAndSettle();

      expect(find.text('学习通'), findsOneWidget);

      // 概览三格（Key 是页面自己定的口径）
      expect(find.byKey(const Key('chaoxingTodoCount')), findsOneWidget);
      expect(find.byKey(const Key('chaoxingUnreadCount')), findsOneWidget);
      expect(find.byKey(const Key('chaoxingCourseCount')), findsOneWidget);
      expect(find.text('1'), findsWidgets, reason: '待做 1 / 未读 1 / 课程 1');

      // 四个区块标题
      expect(find.textContaining('待做作业'), findsWidgets);
      expect(find.textContaining('最近完成'), findsWidgets);
      expect(find.textContaining('通知'), findsWidgets);
      expect(find.textContaining('我的课程'), findsWidgets);

      // 内容行
      expect(find.text('第一章 行列式'), findsOneWidget);
      expect(find.text('关于期中考试安排的通知'), findsOneWidget);
      expect(find.textContaining('线性代数(工)'), findsWidgets);

      expect(tester.takeException(), isNull);
    });

    testWidgets('空快照不崩，且首次进入会自动取数（闸门只拦「有数据」的情形）', (tester) async {
      final controller = _FakeController(ChaoxingSnapshot.empty);
      await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('学习通'), findsOneWidget);
      // `_autoRefreshAll` 的闸门条件是「快照非空 且 窗口未过」→ **空快照必须放行**，
      // 否则新用户进来永远停在空页面（这条是口径，不是巧合）。
      expect(controller.refreshes, 1);
    });
  });

  group('二级页', () {
    testWidgets('作业页：四档筛选各自只留该档', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      addTearDown(tester.view.reset);

      final controller = _FakeController(_snapshot());
      await tester.pumpWidget(_app(const ChaoxingWorksScreen(), controller));
      await tester.pumpAndSettle();

      expect(find.text('第一章 行列式'), findsOneWidget);
      expect(find.text('第二章 矩阵'), findsOneWidget);

      await tester.tap(find.text('已完成（1）'));
      await tester.pumpAndSettle();
      expect(find.text('第二章 矩阵'), findsOneWidget);
      expect(find.text('第一章 行列式'), findsNothing);

      await tester.tap(find.text('待做（1）'));
      await tester.pumpAndSettle();
      expect(find.text('第一章 行列式'), findsOneWidget);
      expect(find.text('第二章 矩阵'), findsNothing);
    });

    testWidgets('通知页：点一行弹全文，且不写任何「已读」', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      addTearDown(tester.view.reset);

      final controller = _FakeController(_snapshot());
      await tester.pumpWidget(_app(const ChaoxingNoticesScreen(), controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('关于期中考试安排的通知'));
      await tester.pumpAndSettle();
      // 列表行本身也有摘要 → 必须**只在弹窗里**找全文，否则会命中两处。
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('期中考试定于第 8 周'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(controller.refreshes, 0, reason: '只读：看通知不触发任何写操作');
    });
    testWidgets('课程页：展开一门课能看到它的作业', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      addTearDown(tester.view.reset);

      final controller = _FakeController(_snapshot());
      await tester.pumpWidget(_app(const ChaoxingCoursesScreen(), controller));
      await tester.pumpAndSettle();

      expect(find.textContaining('线性代数(工)'), findsWidgets);
      await tester.tap(find.textContaining('线性代数(工)').first);
      await tester.pumpAndSettle();
      expect(find.text('第一章 行列式'), findsOneWidget);
      expect(find.text('第三章 向量组'), findsOneWidget);
    });
  });

  group('概览卡动作', () {
    testWidgets('刷新按钮会真的调 refresh（且不抛）', (tester) async {
      final controller = _FakeController(_snapshot());
      await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
      await tester.pumpAndSettle();

      final before = controller.refreshes; // 进入页面时的那一次
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(controller.refreshes, before + 1);
    });

    testWidgets('★ 手动刷新带 force（才越得过风控冷却），自动刷新不带', (tester) async {
      // 口径（用户 2026-09-19 报「刷新会刷新没」之后定的）：仓库命中风控会进
      // 冷却窗口，**自动刷新**（进入页面 / 返回 / 回前台）必须尊重它，否则会在
      // 验证码窗口里反复撞墙；**手动**下拉 / 点刷新是用户明确要求，允许越过。
      final controller = _FakeController(_snapshot());
      await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
      await tester.pumpAndSettle();

      expect(
        controller.refreshes,
        greaterThan(0),
        reason: '进入页面会自动取一次数',
      );
      expect(
        controller.forcedRefreshes,
        0,
        reason: '自动那一次不许带 force',
      );

      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(controller.forcedRefreshes, 1, reason: '点刷新 = 手动 = force');
    });
  });

  group('消息点击看详情（用户 2026-09-19：「我希望消息可以点击看详情」）', () {
    testWidgets('主页「通知消息」区块的行直接可点，弹全文；课程名查得到才印', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);

      final controller = _FakeController(_snapshot());
      await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
      await tester.pumpAndSettle();
      // 进入页面本身会自动刷新（次数是页面自己的口径，别钉死）；这里只关心
      // **点消息前后取数次数不变** —— 只读、不改「已读」。
      final before = controller.refreshes;
      // ① 无课程归属的通知（n1）：只有发件人/时间 + 正文，**不印「所属课程」**
      await tester.tap(find.text('关于期中考试安排的通知'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('期中考试定于第 8 周'),
        ),
        findsOneWidget,
        reason: '主页不再只是跳「全部通知」，本行就得能看全文',
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('所属课程'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('教务处'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      // ② 带 courseId 的通知（n2）：多一行「所属课程」，且是**课程名**不是裸 id
      await tester.tap(find.text('作业提醒'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('所属课程：${_course.name}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(_course.courseId),
        ),
        findsNothing,
        reason: 'courseId 是内部编号，不许回显给用户',
      );

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      // 2026-09-20 收敛：本页**撤掉了 `subscribeRoute`** —— 弹窗（也是路由）关掉不再
      // 触发「返回即刷新」，所以计数必须纹丝不动。下面两条同时守住「只读」。
      expect(
        controller.refreshes,
        before,
        reason: '看消息 / 关弹窗都不该取数（一次取数 ~70 个请求）',
      );
      expect(controller.noticeRefreshes, 0);
      expect(controller.clears, 0);
    });

    testWidgets('★ 从子页面返回只刷新一次（撤 subscribeRoute 的另一半理由）', (tester) async {
      // 口径（2026-09-20 收敛，AGENTS.md §3「能 await push 就 await push，并撤掉
      // subscribeRoute」）：本页只保留 `push().then(刷新)` **一条**「返回即刷新」路径。
      // 从前它与 `RouteAware.didPopNext` 并存 → 同一次返回触发两次自动刷新。
      final controller = _FakeController(_snapshot());
      await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
      await tester.pumpAndSettle();

      final before = controller.refreshes; // 进入页面那一次
      await tester.tap(find.text('查看全部作业'));
      await tester.pumpAndSettle();
      expect(controller.refreshes, before, reason: '进子页面本身不取数');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        controller.refreshes,
        before + 1,
        reason: '返回刷新一次，且**只有一次**（两条路径并存时会 +2）',
      );
    });

    testWidgets('可点性有可见提示：传了 onTap 才出右箭头', (tester) async {
      const notice = ChaoxingNotice(
        id: 'n9',
        title: '测试通知',
        content: '正文',
        sender: '学习通',
      );
      final now = DateTime(2026, 9, 19, 12);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChaoxingNoticeRow(notice: notice, now: now)),
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChaoxingNoticeRow(
              notice: notice,
              now: now,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });
  });

  group('作业点击看详情（用户 2026-09-19：「也做」→ 与通知同一套）', () {
    testWidgets('全部作业页：点一行弹详情（状态 / 绝对时刻 / 课程；「剩余」只给待做）', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 2000);
      addTearDown(tester.view.reset);

      final controller = _FakeController(_snapshot());
      await tester.pumpWidget(_app(const ChaoxingWorksScreen(), controller));
      await tester.pumpAndSettle();

      // 待做（w1）：开始时间缺失给「—」，有「剩余」行
      await tester.tap(find.text('第一章 行列式'));
      await tester.pumpAndSettle();
      expect(_inDialog('待做'), findsOneWidget);
      expect(_inDialog('2026-09-20 23:59'), findsOneWidget, reason: '截止用绝对时刻');
      expect(_inDialog('剩余'), findsOneWidget);
      expect(_inDialog('—'), findsOneWidget, reason: '开始时间缺失');
      expect(_inDialog(_course.name), findsOneWidget, reason: '课程名进详情');

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      // 已完成（w2）：状态自带分数；**没有**「剩余」——
      // 已完成/待批阅谈「已过期 X」是误导（与 `ChaoxingWork.isOverdueAt` 同口径）
      await tester.tap(find.text('第二章 矩阵'));
      await tester.pumpAndSettle();
      expect(_inDialog('已完成 90 分'), findsOneWidget);
      expect(_inDialog('2026-09-10 23:59'), findsOneWidget);
      expect(_inDialog('剩余'), findsNothing);
    });

    testWidgets('主页两个作业区块的行直接可点（不必先进「全部作业」）', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);

      final controller = _FakeController(_snapshot());
      await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
      await tester.pumpAndSettle();

      // 待做作业区块
      await tester.tap(find.text('第一章 行列式'));
      await tester.pumpAndSettle();
      expect(_inDialog('2026-09-20 23:59'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      // 最近完成区块
      await tester.tap(find.text('第二章 矩阵'));
      await tester.pumpAndSettle();
      expect(_inDialog('已完成 90 分'), findsOneWidget);
    });

    testWidgets('作业行同样「传了 onTap 才出右箭头」', (tester) async {
      final work = ChaoxingWork(
        workId: 'w9',
        title: '第九章 二次型',
        courseId: _course.courseId,
        courseName: _course.name,
        dueAt: DateTime(2026, 9, 22, 23, 59),
        status: ChaoxingWorkStatus.todo,
      );
      final now = DateTime(2026, 9, 19, 12);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChaoxingWorkRow(work: work, now: now)),
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChaoxingWorkRow(work: work, now: now, onTap: () {}),
          ),
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });
  });

  group(
    '★ 未扫到的课如实说（用户 2026-09-20：「我明明有一项线性代数的作业，为什么提示没有作业」）',
    () {
      /// 一门课：作业清单**本轮没扫到**（分批轮转的窗口外 / 撞风控后收手）。
      ChaoxingSnapshot pendingOnly() => ChaoxingSnapshot(
        courses: const [_course],
        pendingCourseKeys: const ['100000002/200000002'],
        fetchedAt: DateTime(2026, 9, 20, 0, 30),
      );

      testWidgets('全部课程页：未扫到写「本轮未扫到」，不写「这门课没有作业记录」', (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(1000, 1600);
        addTearDown(tester.view.reset);

        final controller = _FakeController(pendingOnly());
        await tester.pumpWidget(_app(const ChaoxingCoursesScreen(), controller));
        await tester.pumpAndSettle();

        expect(find.text('无作业记录'), findsOneWidget, reason: '条数那行照旧（它是「已知条数」）');
        expect(find.textContaining('本轮未扫到'), findsOneWidget);

        await tester.tap(find.textContaining('线性代数'));
        await tester.pumpAndSettle();
        expect(find.text('这门课没有作业记录'), findsNothing, reason: '「没扫到」≠「没作业」');
        expect(find.textContaining('本轮未扫到'), findsNWidgets(2), reason: '副标题 + 展开正文');
      });

      testWidgets('主页「待做作业」空态：有未扫到的课就得标注可能有遗漏', (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(1000, 2400);
        addTearDown(tester.view.reset);

        final controller = _FakeController(pendingOnly());
        await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
        await tester.pumpAndSettle();

        expect(find.textContaining('暂时没有待做作业'), findsOneWidget);
        expect(find.textContaining('另有 1 门课本轮未扫到'), findsOneWidget);
      });
    },
  );

  group('★ 签到记录（用户 2026-10-09：「我希望还能接入学习通里的签到记录」）', () {
    /// 三条签到：一条**进行中**（未查状态）、一条已签、一条缺勤。
    ///
    /// ⚠ 时间用**相对 now**：页面读的是真实时钟（`_now = DateTime.now()`）。
    ChaoxingSnapshot signSnapshot({List<String> failedSignCourses = const []}) {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      return ChaoxingSnapshot(
        courses: const [_course],
        signs: [
          ChaoxingSign(
            activeId: '6000000000001',
            courseId: _course.courseId,
            classId: '200000002',
            courseName: _course.name,
            typeName: '二维码签到',
            startAt: now.subtract(const Duration(minutes: 5)),
            endAt: now.add(const Duration(minutes: 55)),
            attendCount: 12,
          ),
          ChaoxingSign(
            activeId: '6000000000003',
            courseId: _course.courseId,
            classId: '200000002',
            courseName: _course.name,
            typeName: '手势签到',
            startAt: yesterday,
            endAt: yesterday.add(const Duration(minutes: 13)),
            attendCount: 64,
            status: ChaoxingSignStatus.signed,
            signedAt: yesterday.add(const Duration(seconds: 25)),
            statusLoaded: true,
          ),
          ChaoxingSign(
            activeId: '6000000000004',
            courseId: _course.courseId,
            classId: '200000002',
            courseName: _course.name,
            typeName: '位置签到',
            startAt: yesterday.subtract(const Duration(days: 2)),
            endAt: yesterday.subtract(const Duration(days: 2)),
            attendCount: 60,
            status: ChaoxingSignStatus.absent,
            statusLoaded: true,
          ),
        ],
        failedSignCourseKeys: failedSignCourses,
        fetchedAt: now,
      );
    }

    testWidgets('主页区块：进行中排最前、状态未知写「状态未知」而不是「未签」', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 2600);
      addTearDown(tester.view.reset);

      final controller = _FakeController(signSnapshot());
      await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
      await tester.pumpAndSettle();

      expect(find.text('签到记录'), findsOneWidget);
      expect(find.text('二维码签到'), findsOneWidget);
      expect(find.text('进行中'), findsWidgets, reason: '进行中那条右侧有标记');
      expect(
        find.text('状态未知'),
        findsOneWidget,
        reason: '清单接口不给我的状态 —— 说「未签」就是骗人',
      );
      expect(find.text('已签'), findsOneWidget);
      expect(find.text('缺勤'), findsOneWidget);
      expect(find.textContaining('签到 64 人'), findsOneWidget);

      // 三枚概览 metric
      expect(find.byKey(const Key('chaoxingSignCount')), findsOneWidget);
      expect(find.byKey(const Key('chaoxingOpenSignCount')), findsOneWidget);
      expect(find.byKey(const Key('chaoxingAbsentSignCount')), findsOneWidget);
      expect(find.text('进行中 1 · 共 3 次 · 已签 1 · 未签 1'), findsOneWidget);
    });

    testWidgets('主页区块空态：签到没取到的课要如实说', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 2600);
      addTearDown(tester.view.reset);

      final controller = _FakeController(
        signSnapshot(failedSignCourses: const ['100000002/200000002'])
            .copyWith(signs: const []),
      );
      await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
      await tester.pumpAndSettle();

      expect(find.textContaining('暂时没有签到记录'), findsOneWidget);
      expect(find.textContaining('另有 1 门课的签到没取到'), findsOneWidget);
    });

    testWidgets('点开一条：弹窗给「查询我的状态」，点了就查（1 请求）', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 2600);
      addTearDown(tester.view.reset);

      final controller = _FakeController(signSnapshot());
      await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('二维码签到'));
      await tester.pumpAndSettle();

      expect(_inDialog('我的状态'), findsOneWidget);
      expect(_inDialog('状态未知'), findsWidgets);
      final load = find.byKey(const Key('chaoxingSignLoadStatus'));
      expect(load, findsOneWidget, reason: '状态未知时才给这颗按钮');

      await tester.tap(load);
      await tester.pumpAndSettle();
      expect(controller.signDetailCalls, 1, reason: '按需查询 = 1 个请求');
    });

    testWidgets('已查过的条目：详情直接给状态 + 签到时刻，不再给查询按钮', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 2600);
      addTearDown(tester.view.reset);

      final controller = _FakeController(signSnapshot());
      await tester.pumpWidget(_app(const ChaoxingScreen(), controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('手势签到'));
      await tester.pumpAndSettle();

      expect(_inDialog('已签'), findsWidgets);
      expect(_inDialog('签到时间'), findsOneWidget);
      expect(find.byKey(const Key('chaoxingSignLoadStatus')), findsNothing);
    });

    testWidgets('「全部签到」页：按课程分组 + 两个手动按钮（都先确认再跑）', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 2600);
      addTearDown(tester.view.reset);

      final controller = _FakeController(signSnapshot());
      await tester.pumpWidget(_app(const ChaoxingSignsScreen(), controller));
      await tester.pumpAndSettle();

      expect(find.text('全部签到'), findsOneWidget, reason: 'AppBar 标题');
      expect(find.text('261学期 线性代数(工)'), findsOneWidget, reason: '按课程分组');
      expect(find.textContaining('3 次签到 · 已签 1 · 未签 1 · 1 条状态未查'),
          findsOneWidget);

      // 「补全全部状态」→ 确认弹窗 → 开始
      await tester.tap(find.byKey(const Key('chaoxingSignFillStatus')));
      await tester.pumpAndSettle();
      expect(find.text('补全全部签到状态？'), findsOneWidget);
      await tester.tap(find.byKey(const Key('chaoxingSignFullUpdateConfirm')));
      await tester.pumpAndSettle();
      expect(controller.signFullCalls, 1);
      expect(controller.signFullAllCourses, isFalse, reason: '默认只本学期');

      // 「含往期课程一起更新」→ allCourses = true
      await tester.tap(find.byKey(const Key('chaoxingSignFullUpdate')));
      await tester.pumpAndSettle();
      expect(find.text('含往期课程更新？'), findsOneWidget);
      await tester.tap(find.byKey(const Key('chaoxingSignFullUpdateConfirm')));
      await tester.pumpAndSettle();
      expect(controller.signFullCalls, 2);
      expect(controller.signFullAllCourses, isTrue);
    });

    testWidgets('「全部签到」页：没取到的课要标出来（不静默）', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 2600);
      addTearDown(tester.view.reset);

      final controller = _FakeController(
        signSnapshot(failedSignCourses: const ['100000002/200000002']),
      );
      await tester.pumpWidget(_app(const ChaoxingSignsScreen(), controller));
      await tester.pumpAndSettle();

      expect(find.textContaining('签到清单本轮没取到'), findsOneWidget);
    });
  });
}
