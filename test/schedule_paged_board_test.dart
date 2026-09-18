import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_paged_board.dart';

/// 竖版课表分页板守卫（用户 2026-09-16 裁定）：
///
/// > 课表我希望横划时，顶部的"周一"、...不动，然后左侧节数列淡化隐藏，
/// > 只有主体部分参与滑动动画，然后松手后，节数列出现
///
/// 本文件用**假页面**（只画「第 N 周 / 周D」文本）验证三件事：
/// ① 主体真的随手指位移（相邻周并排）；② 表头在任何拖动阶段都不动；
/// ③ 节数列拖动时淡出、松手后恢复。
void main() {
  /// 一个「周页」：`Row` 7 列，每列一个可量宽的方块，键为 `scheduleTestDay-<week>-<day>`。
  Widget page(BuildContext context, int week) {
    return Row(
      children: [
        for (int day = 0; day < 7; day++)
          SizedBox(
            key: Key('scheduleTestDay-$week-$day'),
            width: 40,
            child: Center(child: Text('第$week周 周${day + 1}')),
          ),
      ],
    );
  }

  Widget app({
    required int week,
    required ValueChanged<int> onWeekChanged,
    int weekCount = 5,
    bool enabled = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  const SizedBox(
                    key: Key('scheduleTestCorner'),
                    width: 30,
                    child: Text('角'),
                  ),
                  for (int day = 0; day < 7; day++)
                    const SizedBox(width: 40, child: Center(child: Text('周列'))),
                ],
              ),
            ),
            Expanded(
              child: SchedulePagedBoard(
                weekCount: weekCount,
                week: week,
                enabled: enabled,
                onWeekChanged: onWeekChanged,
                bodyHeight: 200,
                leadingWidth: 30,
                header: const SizedBox(
                  key: Key('scheduleTestHeader'),
                  height: 34,
                  child: Text('（表头：周一…周日）', textAlign: TextAlign.center),
                ),
                leading: const SizedBox(
                  key: Key('scheduleTestLeading'),
                  width: 30,
                  child: Text('1'),
                ),
                pageBuilder: page,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double leadingOpacity(WidgetTester tester) {
    final widget = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('scheduleLeadingColumn')),
    );
    return widget.opacity;
  }

  testWidgets('初始：节数列可见、表头在顶部、当前周页面独占视口', (tester) async {
    await tester.pumpWidget(app(week: 2, onWeekChanged: (_) {}));
    await tester.pumpAndSettle();

    expect(leadingOpacity(tester), 1);
    // 主体第 2 周的第 1 天贴着节数列右侧（没有位移）。
    expect(
      tester.getTopLeft(find.byKey(const Key('scheduleTestDay-2-0'))).dx,
      closeTo(
        tester.getTopLeft(find.byKey(const Key('scheduleTestLeading'))).dx + 30,
        0.5,
      ),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拖动中：表头不动，节数列淡出', (tester) async {
    await tester.pumpWidget(app(week: 2, onWeekChanged: (_) {}));
    await tester.pumpAndSettle();

    final headerTopBefore = tester.getTopLeft(
      find.byKey(const Key('scheduleTestHeader')),
    );
    final leadingLeftBefore = tester
        .getTopLeft(find.byKey(const Key('scheduleTestLeading')))
        .dx;

    final gesture = await tester.startGesture(const Offset(200, 120));
    // ⚠️ 分两次移动：第一段被「起手」（touch slop）吃掉，单次 moveBy 不位移。
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();

    // ① 表头完全没动
    expect(
      tester.getTopLeft(find.byKey(const Key('scheduleTestHeader'))),
      headerTopBefore,
    );
    // ② 节数列位置没动（Opacity 保留占位），但已淡出
    expect(
      tester.getTopLeft(find.byKey(const Key('scheduleTestLeading'))).dx,
      closeTo(leadingLeftBefore, 0.5),
    );
    expect(leadingOpacity(tester), SchedulePagedBoard.leadingHiddenOpacity);
    // ③ 主体确实在位移（当前周往左走）
    expect(
      tester.getTopLeft(find.byKey(const Key('scheduleTestDay-2-0'))).dx,
      lessThan(leadingLeftBefore + 30 - 10),
    );
    // ④ 相邻周已经并排出现在右侧
    expect(find.byKey(const Key('scheduleTestDay-3-0')), findsOneWidget);
    // ⑤ 节数列那一栏下面就是**滑动中的课表**（用户 2026-09-16：
    //    「节数列隐藏后，原节数列位置可以显示被滑动的课表」）——
    //    分页视口 = 整块宽度，所以拖动时有课格横向盖住 x∈[0, leadingWidth]。
    final leadingRect = tester.getRect(
      find.byKey(const Key('scheduleTestLeading')),
    );
    final covered = <int>[];
    for (int day = 0; day < 7; day++) {
      final rect = tester.getRect(find.byKey(Key('scheduleTestDay-2-$day')));
      if (rect.left < leadingRect.right && rect.right > leadingRect.left) {
        covered.add(day);
      }
    }
    expect(covered, isNotEmpty, reason: '拖动时节数列那一栏应露出滑动中的课表（节数列已淡出、不遮挡）');
    // ⑥ 节数列是浮层，绝不能吞掉手势（祖先里应有 IgnorePointer —— 拖动本身
    //    能生效也是同一结论的行为证据；这里只做结构守卫，故用 findsWidgets：
    //    PageView / Scrollable 内部本来也带 IgnorePointer）。
    expect(
      find.ancestor(
        of: find.byKey(const Key('scheduleLeadingColumn')),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );

    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('静止时：节数列那一栏下面没有课格（不是把节数列盖在网格上）', (tester) async {
    await tester.pumpWidget(app(week: 2, onWeekChanged: (_) {}));
    await tester.pumpAndSettle();

    final leadingRect = tester.getRect(
      find.byKey(const Key('scheduleTestLeading')),
    );
    for (int day = 0; day < 7; day++) {
      final rect = tester.getRect(find.byKey(Key('scheduleTestDay-2-$day')));
      expect(
        rect.left >= leadingRect.right || rect.right <= leadingRect.left,
        isTrue,
        reason: '第 ${day + 1} 天课格不该压在节数列上（静止时列要对齐表头）',
      );
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('松手后：节数列恢复可见（不论是否翻页成功）', (tester) async {
    final changed = <int>[];
    await tester.pumpWidget(app(week: 2, onWeekChanged: changed.add));
    await tester.pumpAndSettle();

    // 小幅拖动（不过阈值）→ 回弹且不切周
    var gesture = await tester.startGesture(const Offset(200, 120));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    expect(leadingOpacity(tester), SchedulePagedBoard.leadingHiddenOpacity);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(leadingOpacity(tester), 1);
    expect(changed, isEmpty);

    // 大幅拖动（越过半页阈值）→ 翻页
    gesture = await tester.startGesture(const Offset(200, 120));
    await gesture.moveBy(const Offset(-300, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-300, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(leadingOpacity(tester), 1);
    expect(changed, [3]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('程序化改周（点上一周/下一周按钮）：节数列不闪', (tester) async {
    await tester.pumpWidget(app(week: 2, onWeekChanged: (_) {}));
    await tester.pumpAndSettle();

    await tester.pumpWidget(app(week: 3, onWeekChanged: (_) {}));
    await tester.pump(); // 补间第一帧
    // 非手势滚动 → 节数列保持可见（避免按钮切周时闪一下）
    expect(leadingOpacity(tester), 1);
    await tester.pumpAndSettle();
    expect(leadingOpacity(tester), 1);
    expect(
      tester.getTopLeft(find.byKey(const Key('scheduleTestDay-3-0'))).dx,
      closeTo(
        tester.getTopLeft(find.byKey(const Key('scheduleTestLeading'))).dx + 30,
        0.5,
      ),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('enabled=false：拖不动，也不会淡出', (tester) async {
    await tester.pumpWidget(
      app(week: 2, enabled: false, onWeekChanged: (_) {}),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(200, 120));
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    expect(leadingOpacity(tester), 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(leadingOpacity(tester), 1);
    await tester.pumpWidget(const SizedBox());
  });

  test('常量契约：淡出时长与隐藏不透明度', () {
    // 隐藏不透明度 = 0（用户口径「淡化隐藏」）；时长与翻页补间同量级。
    expect(SchedulePagedBoard.leadingHiddenOpacity, 0);
    const board = SchedulePagedBoard(
      weekCount: 1,
      week: 1,
      onWeekChanged: _noop,
      header: SizedBox.shrink(),
      leading: SizedBox.shrink(),
      leadingWidth: 30,
      bodyHeight: 0,
      pageBuilder: _noopPage,
    );
    expect(board.fadeDuration.inMilliseconds, greaterThan(0));
    expect(board.fadeDuration.inMilliseconds, lessThanOrEqualTo(300));
  });
}

void _noop(int _) {}

Widget _noopPage(BuildContext context, int week) => const SizedBox.shrink();
