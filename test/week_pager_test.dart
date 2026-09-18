import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/presentation/week_pager.dart';

/// 用户 2026-09-15：「移动端切换周数的动画太奇怪了，我希望就是很自然像手机桌面
/// 翻页一样」——即
/// ① 拖动时**当前周与相邻周同时**随手指 1:1 位移（两侧都在屏幕上，不露空白）；
/// ② 松手按距离/速度 snap（小幅拖动回弹、快速 fling 也切页）；
/// ③ 首/末周不越界；
/// ④ 外部改周（上一周/下一周按钮、学期切换）走补间或跳转，不与手势打架。
void main() {
  /// 假页面：整页一个「第 N 周」大字 + **按周命名的 Key**（量页面位置用）。
  Widget fakePage(BuildContext context, int week) => SizedBox.expand(
    key: ValueKey('page-$week'),
    child: ColoredBox(
      color: week.isEven ? const Color(0xFFEEEEEE) : const Color(0xFFDDDDDD),
      child: Center(child: Text('第 $week 周')),
    ),
  );

  Future<void> pumpPager(
    WidgetTester tester, {
    int week = 3,
    int weekCount = 10,
    bool enabled = true,
    int smoothRequest = 0,
    required List<int> changed,
    double width = 400,
  }) async {
    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekPager(
            weekCount: weekCount,
            week: week,
            enabled: enabled,
            smoothRequest: smoothRequest,
            onWeekChanged: changed.add,
            pageBuilder: fakePage,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 某一周页面的左边界横坐标（静止时 = 0；跟手拖动时 = 手指位移）。
  ///
  /// 量**页面**而不是页里的文字：文字在页内居中，用它会把「居中留白」当成位移。
  /// ⚠ 只对**已构建**的页面有效 —— `PageView` 的 `cacheExtent` 是 0，正在补间
  /// 时远处的目标页还没进视口、`find` 找不到（量「翻到哪了」要用 [pageOffset]）。
  double pageLeft(WidgetTester tester, int week) =>
      tester.getTopLeft(find.byKey(ValueKey('page-$week'))).dx;

  /// 滚动偏移，单位 = 页（0 = 第 1 周那一页在最左）。
  ///
  /// 用它断言「翻到一半」：补间途中目标页可能尚未构建，`find.byKey` 会落空。
  /// ⚠ 页宽取**真实视口**（`viewportDimension`），别猜参数 —— 测试视口默认是
  /// 800×600 逻辑像素（physical 2400×1800 / dpr 3），写死 400 会把结果算成两倍。
  double pageOffset(WidgetTester tester) {
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(PageView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    return position.pixels / position.viewportDimension;
  }

  testWidgets('静止时只显示当前周，相邻周在屏幕外待命', (tester) async {
    final changed = <int>[];
    await pumpPager(tester, week: 3, changed: changed);

    expect(find.text('第 3 周'), findsOneWidget);
    expect(pageLeft(tester, 3), lessThan(400 * 0.5));
    expect(changed, isEmpty);
  });

  testWidgets('拖动跟手：当前周与相邻周一起位移（不是滑走露出空白）', (tester) async {
    final changed = <int>[];
    await pumpPager(tester, week: 3, changed: changed);

    final before = pageLeft(tester, 3);
    final gesture = await tester.startGesture(const Offset(200, 350));
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();

    final after = pageLeft(tester, 3);
    expect(
      before - after,
      greaterThan(60),
      reason: '当前周要随手指左移（1:1 跟手），实测位移 ${before - after}',
    );
    // 左划时**右侧**邻页同时进入可视区 —— 这就是「像翻页」的关键
    // （旧实现是整屏滑走后露出空白，再硬切新页）。
    expect(
      pageLeft(tester, 4),
      lessThan(400),
      reason: '右邻页应同时出现在屏幕上（左边界 ${pageLeft(tester, 4)}）',
    );
    expect(changed, isEmpty, reason: '还没松手不该回调');

    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump();
  });

  testWidgets('过阈值松手 → snap 到下一周，且相邻周接管屏幕', (tester) async {
    final changed = <int>[];
    await pumpPager(tester, week: 3, changed: changed);

    await tester.drag(find.byType(PageView), const Offset(-220, 0));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(changed, [4], reason: '左划一页 = 下一周');
    expect(pageLeft(tester, 4), lessThan(1), reason: '第 4 周接管屏幕');
  });

  testWidgets('右划 → 上一周', (tester) async {
    final changed = <int>[];
    await pumpPager(tester, week: 3, changed: changed);

    await tester.drag(find.byType(PageView), const Offset(220, 0));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(changed, [2]);
    expect(pageLeft(tester, 2), lessThan(1));
  });

  testWidgets('小幅慢拖 → 回弹，不换周', (tester) async {
    final changed = <int>[];
    await pumpPager(tester, week: 3, changed: changed);

    final gesture = await tester.startGesture(const Offset(200, 350));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump();

    expect(changed, isEmpty, reason: '位移不够且速度慢 → 回弹到原周');
    expect(pageLeft(tester, 3).abs(), lessThan(1));
  });

  testWidgets('快速 fling（位移小但速度快）也切页 —— 桌面/手机同款手感', (tester) async {
    final changed = <int>[];
    await pumpPager(tester, week: 3, changed: changed);

    await tester.fling(find.byType(PageView), const Offset(-60, 0), 1200);
    await tester.pumpAndSettle();
    await tester.pump();

    expect(changed, [4], reason: 'fling 由速度判定，不只看拖了多远');
  });

  testWidgets('首周右划不越界', (tester) async {
    final changed = <int>[];
    await pumpPager(tester, week: 1, changed: changed);
    await tester.drag(find.byType(PageView), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(changed, isEmpty);
    expect(pageLeft(tester, 1).abs(), lessThan(1));
  });

  testWidgets('末周左划不越界', (tester) async {
    final changed = <int>[];
    await pumpPager(tester, week: 10, weekCount: 10, changed: changed);
    await tester.drag(find.byType(PageView), const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(changed, isEmpty, reason: '末周没有下一页');
    expect(pageLeft(tester, 10), lessThan(1));
  });

  testWidgets('越界的 week 被夹进 [1, weekCount]', (tester) async {
    final changed = <int>[];
    await pumpPager(tester, week: 99, weekCount: 8, changed: changed);
    expect(find.text('第 8 周'), findsOneWidget, reason: '99 → 末周');
    expect(changed, isEmpty);
  });

  testWidgets('外部改周（±1）走补间；跨多周直接跳', (tester) async {
    final changed = <int>[];
    await pumpPager(tester, week: 3, changed: changed);

    // ±1：补间（中间帧不在任何一页位置上）
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekPager(
            weekCount: 10,
            week: 4,
            onWeekChanged: changed.add,
            pageBuilder: fakePage,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final mid = pageLeft(tester, 4);
    expect(mid.abs(), greaterThan(1), reason: '补间途中应处在两页之间（实测偏移 $mid）');
    await tester.pumpAndSettle();
    expect(pageLeft(tester, 4).abs(), lessThan(1));

    // 跨多周（4 → 9）：直接跳到位，无需逐页刷
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekPager(
            weekCount: 10,
            week: 9,
            onWeekChanged: changed.add,
            pageBuilder: fakePage,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(pageLeft(tester, 9).abs(), lessThan(1));
  });

  testWidgets('enabled=false（桌面）：拖动不翻页，但外部改周仍生效', (tester) async {
    final changed = <int>[];
    await pumpPager(tester, week: 3, enabled: false, changed: changed);

    await tester.drag(find.byType(PageView), const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(changed, isEmpty, reason: '桌面用按钮切周，不响应滑动');
    expect(pageLeft(tester, 3).abs(), lessThan(1));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekPager(
            weekCount: 10,
            week: 4,
            enabled: false,
            onWeekChanged: changed.add,
            pageBuilder: fakePage,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(pageLeft(tester, 4).abs(), lessThan(1), reason: '按钮切周仍然生效');
  });

  test('时长契约', () {
    expect(WeekPager.pageTransition, const Duration(milliseconds: 280));
    expect(WeekPager.jumpThreshold, 1);
  });

  // ─── 长按回本周的横划动画（用户 2026-09-17）────────────────────────
  //
  // 「长按周数返回本周要显示横划动画」——回本周常常跨十几周，从前一律
  // `jumpToPage` 瞬移；`smoothRequest` 序号变化时改为**跨多少周都补间**，
  // 且补间途中的逐页上报不许把自己拽回去。

  group('平滑跳转（长按回本周）', () {
    test('跨页时长：一页 = 单页时长，每多一页 +45ms，封顶 700ms', () {
      expect(WeekPager.smoothTransitionFor(1), WeekPager.pageTransition);
      expect(
        WeekPager.smoothTransitionFor(2),
        const Duration(milliseconds: 325),
      );
      expect(
        WeekPager.smoothTransitionFor(19),
        WeekPager.smoothMaxTransition,
        reason: '再远也不拖过 700ms',
      );
      expect(WeekPager.smoothTransitionFor(0), WeekPager.pageTransition);
      expect(WeekPager.smoothTransitionFor(-5), WeekPager.pageTransition);
      // 单调不减：跨得越多给得越久（直到封顶）
      var last = Duration.zero;
      for (var pages = 1; pages <= 19; pages++) {
        final d = WeekPager.smoothTransitionFor(pages);
        expect(d >= last, isTrue, reason: '$pages 页的时长不应短于上一档');
        last = d;
      }
    });

    testWidgets('请求平滑 + 跨多周 → 补间（不是瞬移）', (tester) async {
      final changed = <int>[];
      await pumpPager(tester, week: 3, weekCount: 20, changed: changed);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeekPager(
              weekCount: 20,
              week: 13,
              // 序号 0 → 1 = 外部请求这次横划过去
              smoothRequest: 1,
              onWeekChanged: changed.add,
              pageBuilder: fakePage,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final mid = pageOffset(tester);
      expect(
        mid,
        greaterThan(2.0 + 0.01),
        reason: '补间途中已经离开第 3 周页（实测偏移 $mid 页）—— 瞬移的话仍会是 2.0',
      );
      expect(
        mid,
        lessThan(12.0 - 0.01),
        reason: '补间途中还没到第 13 周页（实测偏移 $mid 页）',
      );
      await tester.pumpAndSettle();
      expect(
        pageOffset(tester),
        moreOrLessEquals(12.0, epsilon: 0.01),
        reason: '最终停在目标周（第 13 周 = 下标 12）',
      );
    });

    testWidgets('不请求平滑的跨多周仍然是瞬移（弹窗选周 / 切学期）', (tester) async {
      final changed = <int>[];
      await pumpPager(tester, week: 3, weekCount: 20, changed: changed);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeekPager(
              weekCount: 20,
              week: 13,
              onWeekChanged: changed.add,
              pageBuilder: fakePage,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        pageOffset(tester),
        moreOrLessEquals(12.0, epsilon: 0.01),
        reason: '没有平滑请求 → 直接到位（第 13 周 = 下标 12），不逐页刷',
      );
    });

    testWidgets('补间途中的逐页上报不会被当成外部改周把自己拽回去', (tester) async {
      // 宿主镜像课表页：`onWeekChanged` → `setState(_week = week)`（周数回灌）。
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey<_HostState>();
      final changed = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _Host(key: key, changed: changed),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 长按回本周：第 9 周 → 第 3 周（跨 6 周），走平滑
      key.currentState!.goToWeek(3, smooth: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final mid = pageOffset(tester);
      expect(
        mid,
        lessThan(8.0 - 0.01),
        reason: '补间应已经在移动（实测 $mid 页，起点 8.0）',
      );
      expect(mid, greaterThan(2.0 + 0.01), reason: '补间应还在途中');
      // 该档时长 = 280 + 5×45 = 505ms：再给 700ms 必须已经到位，
      // 被逐页回声拽回的话会一直回不到目标。
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        pageOffset(tester),
        moreOrLessEquals(2.0, epsilon: 0.01),
        reason: '补间必须按时到位；被逐页回声拽回会停在别处',
      );
      await tester.pumpAndSettle();
      expect(find.text('第 3 周'), findsOneWidget);
      expect(
        changed.where((w) => w > 3 && w < 9),
        isNotEmpty,
        reason: '跨周补间应逐页上报（标题栏周数跟着数上去）',
      );
      expect(changed.last, 3);
    });

    test('源码守卫：长按回本周走平滑请求、两个视图都收到它', () {
      final src = File(
        'lib/features/ims/schedule/presentation/schedule_screen.dart',
      ).readAsStringSync();
      expect(
        'onReturnToCurrentWeek: (week) => _goToWeek(week, smooth: true)'
            .allMatches(src)
            .length,
        2,
        reason: '两个周次入口（AppBar 标题栏 + 内嵌工具条）都要走平滑那条路',
      );
      expect(
        src.contains('pagerSmoothRequest: _smoothWeekRequest'),
        isTrue,
        reason: '竖版（网格）要把平滑请求透传给 SchedulePagedBoard',
      );
      expect(
        src.contains('smoothRequest: _smoothWeekRequest'),
        isTrue,
        reason: '横版直接建 WeekPager，也要传',
      );
      // 弹窗选周 / 切学期是定位语义，不许变成横划
      expect(
        'smooth: true'.allMatches(src).length,
        2,
        reason: '只有长按回本周那一处允许 smooth: true（另一处是 _goToWeek 自身的参数默认值调用点）',
      );
    });
  });
}

/// 受控宿主：把分页器上报的周**同步回** `week`（镜像课表页 `_onPagerWeekChanged`
/// → `setState(() => _week = week)`），并可发起「外部改周」（普通 / 平滑）。
class _Host extends StatefulWidget {
  const _Host({super.key, required this.changed});

  final List<int> changed;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int _week = 9;
  int _smooth = 0;

  /// 外部改周；[smooth] = true 表示要求横划过去（长按回本周）。
  void goToWeek(int week, {bool smooth = false}) {
    setState(() {
      _week = week;
      if (smooth) _smooth++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WeekPager(
      weekCount: 20,
      week: _week,
      smoothRequest: _smooth,
      onWeekChanged: (week) {
        widget.changed.add(week);
        setState(() => _week = week);
      },
      pageBuilder: (context, week) => SizedBox.expand(
        key: ValueKey('page-$week'),
        child: Center(child: Text('第 $week 周')),
      ),
    );
  }
}
