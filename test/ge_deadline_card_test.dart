/// 课程「截止日期」卡与编辑弹层的界面守卫。
///
/// ⚠ 两个坑（踩过）：
/// 1. 卡片自带 30 秒倒计时节拍，测试一律传 `tickInterval: Duration.zero` 并注入固定
///    `now`，否则 `pumpAndSettle` 会被周期性重建拖到超时；
/// 2. `FilledButton.icon` 的真实类型是私有子类，`find.byType(FilledButton)` /
///    `widgetWithText(FilledButton, …)` **匹配不到**（byType 是精确类型匹配）→
///    一律用 `find.text('保存')` 定位；另外底部弹层内容比默认 800×600 视口高，
///    弹层里的测试要先放大视口，否则按钮在视口外点不到。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/score_estimate/domain/ge_deadline.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_deadline_card.dart';

final DateTime kNow = DateTime(2026, 10, 8, 12);

GeDeadline deadline({
  String id = 'd1',
  String title = '第 3 章习题',
  GeDeadlineKind kind = GeDeadlineKind.homework,
  required DateTime dueAt,
  GeDeadlineRepeat repeat = GeDeadlineRepeat.none,
  String note = '',
  DateTime? doneAt,
  bool remind = true,
}) => GeDeadline(
  id: id,
  title: title,
  kind: kind,
  dueAt: dueAt,
  repeat: repeat,
  note: note,
  doneAt: doneAt,
  remind: remind,
);

Future<void> pumpCard(
  WidgetTester tester, {
  required List<GeDeadline> deadlines,
  VoidCallback? onAdd,
  ValueChanged<GeDeadline>? onEdit,
  ValueChanged<GeDeadline>? onToggleDone,
  ValueChanged<GeDeadline>? onDelete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GeDeadlineCard(
            deadlines: deadlines,
            now: kNow,
            tickInterval: Duration.zero,
            onAdd: onAdd ?? () {},
            onEdit: onEdit ?? (_) {},
            onToggleDone: onToggleDone ?? (_) {},
            onDelete: onDelete ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('截止日期卡', () {
    testWidgets('空态：给出说明与两个添加入口', (tester) async {
      var added = 0;
      await pumpCard(tester, deadlines: const [], onAdd: () => added++);

      expect(find.text('截止日期'), findsOneWidget);
      expect(find.textContaining('还没有截止日期'), findsOneWidget);
      expect(find.textContaining('记下网课、作业、考试的截止时间'), findsOneWidget);

      // 空态里有两个「添加」入口：标题右侧一个、空态行尾一个。
      // ⚠ 标题那个是 `TextButton.icon`（私有子类），`widgetWithText(TextButton,…)`
      //    只匹配得到行尾那个 → 这里按文本定位。
      final addTexts = find.text('添加');
      expect(addTexts, findsNWidgets(2));
      await tester.tap(addTexts.first);
      await tester.pump();
      expect(added, 1);
      await tester.tap(addTexts.last);
      await tester.pump();
      expect(added, 2);
    });

    testWidgets('有数据：标题 / 类型角标 / 倒计时 / 备注 / 重复与提醒标记', (tester) async {
      await pumpCard(
        tester,
        deadlines: [
          deadline(
            id: 'a',
            title: '网课第 2 讲测验',
            kind: GeDeadlineKind.onlineCourse,
            dueAt: DateTime(2026, 10, 8, 23, 59),
            note: '超星学习通 · 需提交 PDF',
          ),
          deadline(
            id: 'b',
            title: '第 3 章习题',
            // 每周锚点 09-18 → 下一个未来截止 = 10-09（不是今天）
            dueAt: DateTime(2026, 9, 18, 23, 59),
            repeat: GeDeadlineRepeat.weekly,
            remind: false,
          ),
        ],
      );

      expect(find.text('网课第 2 讲测验'), findsOneWidget);
      expect(find.text('今天 23:59 截止'), findsOneWidget);
      expect(find.text('超星学习通 · 需提交 PDF'), findsOneWidget);
      expect(find.text('网课'), findsOneWidget);
      expect(find.text('10-09 23:59 · 每周'), findsOneWidget);
      expect(find.text('还剩 1 天 11 小时'), findsOneWidget);
      // 关掉提醒的那条不出铃铛（开启的那条出）
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
      expect(find.text('共 2 条 · 还有 2 条未完成'), findsOneWidget);
    });

    testWidgets('已完成：删除线 + 「已完成」chip，且不再计入未完成', (tester) async {
      await pumpCard(
        tester,
        deadlines: [
          deadline(
            id: 'a',
            title: '第 1 章习题',
            dueAt: DateTime(2026, 10, 1),
            doneAt: DateTime(2026, 9, 30),
          ),
          deadline(id: 'b', title: '第 2 章习题', dueAt: DateTime(2026, 10, 20)),
        ],
      );

      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('共 2 条 · 还有 1 条未完成'), findsOneWidget);
      final text = tester.widget<Text>(find.text('第 1 章习题'));
      expect(text.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('勾选完成 / 取消完成都把该条回调出去', (tester) async {
      final hits = <String>[];
      await pumpCard(
        tester,
        deadlines: [deadline(id: 'a', dueAt: DateTime(2026, 10, 20))],
        onToggleDone: (d) => hits.add('toggle:${d.id}'),
      );

      await tester.tap(find.byIcon(Icons.radio_button_unchecked));
      await tester.pump();
      expect(hits, ['toggle:a']);

      await pumpCard(
        tester,
        deadlines: [
          deadline(
            id: 'a',
            dueAt: DateTime(2026, 10, 20),
            doneAt: DateTime(2026, 10, 7),
          ),
        ],
        onToggleDone: (d) => hits.add('untoggle:${d.id}'),
      );
      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pump();
      expect(hits.last, 'untoggle:a');
    });

    testWidgets('点行 = 编辑；菜单 = 编辑 / 删除', (tester) async {
      final events = <String>[];
      await pumpCard(
        tester,
        deadlines: [
          deadline(id: 'a', title: '第 3 章习题', dueAt: DateTime(2026, 10, 20)),
        ],
        onEdit: (d) => events.add('edit:${d.id}'),
        onDelete: (d) => events.add('delete:${d.id}'),
      );

      await tester.tap(find.text('第 3 章习题'));
      await tester.pump();
      expect(events, ['edit:a']);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(events.last, 'delete:a');
    });

    testWidgets('卡脚说明提醒口径与重复滚动', (tester) async {
      await pumpCard(
        tester,
        deadlines: [deadline(dueAt: DateTime(2026, 10, 20))],
      );
      expect(find.textContaining('提前 1 天 + 提前 1 小时'), findsOneWidget);
      expect(find.textContaining('自动滚到下一次'), findsOneWidget);
    });
  });

  group('截止日期编辑弹层', () {
    /// 放大视口：弹层内容（含底部按钮）在默认 800×600 里会超出可点区域。
    void useLargeViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    /// 挂一个宿主页面 + 「open」按钮，打开弹层；返回读取结果的闭包。
    Future<GeDeadline? Function()> mountEditor(
      WidgetTester tester, {
      GeDeadline? existing,
    }) async {
      GeDeadline? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showGeDeadlineEditor(
                      context,
                      existing: existing,
                      now: kNow,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => result;
    }

    testWidgets('默认值：类型=作业、截止=今天 23:59、提醒开；标题为空不能保存', (tester) async {
      useLargeViewport(tester);
      final read = await mountEditor(tester);

      expect(find.text('添加截止日期'), findsOneWidget);
      expect(find.text('10-08'), findsOneWidget);
      expect(find.text('23:59'), findsOneWidget);
      expect(find.text('提前 1 天 + 提前 1 小时（系统通知）'), findsOneWidget);

      // 标题为空 → 保存点了也关不掉（按钮禁用）
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('添加截止日期'), findsOneWidget);
      expect(read(), isNull);
    });

    testWidgets('填标题 + 选网课/每周 → 保存返回带默认提醒与重复规则的记录', (tester) async {
      useLargeViewport(tester);
      final read = await mountEditor(tester);

      await tester.enterText(find.byType(TextField).first, '网课第 2 讲测验');
      await tester.pump();
      await tester.tap(find.text('网课'));
      await tester.pump();
      await tester.tap(find.text('每周'));
      await tester.pump();
      expect(find.textContaining('自动滚到下一个未到期的时刻'), findsOneWidget);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final result = read();
      expect(result, isNotNull);
      expect(result!.title, '网课第 2 讲测验');
      expect(result.kind, GeDeadlineKind.onlineCourse);
      expect(result.repeat, GeDeadlineRepeat.weekly);
      expect(result.remind, isTrue);
      expect(result.dueAt, DateTime(2026, 10, 8, 23, 59));
      expect(result.id.isNotEmpty, isTrue);
      expect(find.text('添加截止日期'), findsNothing, reason: '保存后关闭');
    });

    testWidgets('编辑已有条目：字段回填，关掉提醒后保存且不改 id', (tester) async {
      useLargeViewport(tester);
      final existing = deadline(
        id: 'keep-me',
        title: '第 4 章习题',
        kind: GeDeadlineKind.exam,
        dueAt: DateTime(2026, 10, 15, 18),
        repeat: GeDeadlineRepeat.biweekly,
        note: '闭卷',
      );
      final read = await mountEditor(tester, existing: existing);

      expect(find.text('编辑截止日期'), findsOneWidget);
      expect(find.text('第 4 章习题'), findsOneWidget);
      expect(find.text('10-15'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);
      expect(find.text('闭卷'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final result = read();
      expect(result!.id, 'keep-me', reason: '编辑不改 id');
      expect(result.remind, isFalse);
      expect(result.repeat, GeDeadlineRepeat.biweekly);
      expect(result.kind, GeDeadlineKind.exam);
      expect(result.note, '闭卷');
    });

    testWidgets('取消 → 返回 null', (tester) async {
      useLargeViewport(tester);
      final read = await mountEditor(tester);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(read(), isNull);
      expect(find.text('添加截止日期'), findsNothing);
    });

    testWidgets('默认截止时刻：现在已过 23:59 时顺延到明天', (tester) async {
      expect(
        geDeadlineDefaultDue(DateTime(2026, 10, 8, 12)),
        DateTime(2026, 10, 8, 23, 59),
      );
      expect(
        geDeadlineDefaultDue(DateTime(2026, 10, 9, 1)),
        DateTime(2026, 10, 9, 23, 59),
      );
    });
  });
}
