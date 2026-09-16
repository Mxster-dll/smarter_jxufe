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
  double pageLeft(WidgetTester tester, int week) =>
      tester.getTopLeft(find.byKey(ValueKey('page-$week'))).dx;

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
}
