import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/public_query/domain/public_timetable.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/public_timetable_view.dart';

/// 公共查询课表卡片的**渲染**守卫。
///
/// 历史 bug（2026-09-14 用户实测）：「查询到 1 个课程的课表」显示出来了，
/// 课表本身却一片空白 —— 网格每一行用了
/// `Row(crossAxisAlignment: CrossAxisAlignment.stretch)`，而卡片挂在滚动页的
/// **无界高度**里（ListView 子项），stretch 会给第一个非弹性子项（左侧行标签
/// `SizedBox`）传 `BoxConstraints.tightFor(height: Infinity)` →
/// `BoxConstraints forces an infinite height` → 卡片布局整体失败、网格画不出来。
///
/// 这个文件的作用就是「在真实上下文里把卡片画一遍」：只要再有人把 stretch 写回来，
/// `tester.takeException()` 立刻变红。
void main() {
  List<PublicTimetable> load(String fixture, List<String> prefixes) =>
      parsePublicTimetableReport(
        File('test/fixtures/$fixture').readAsStringSync(),
        ownerPrefixes: prefixes,
      );

  /// 卡片在页面里的真实处境：滚动容器的子项（**无界高度**）。
  Future<void> pumpInScrollPage(WidgetTester tester, Widget card) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(padding: const EdgeInsets.all(12), children: [card]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String spanLabel(PublicTimetableCell c) => c.startPeriod == c.endPeriod
      ? '${c.startPeriod}节'
      : '${c.startPeriod}-${c.endPeriod}节';

  group('课表卡片在滚动页里的渲染', () {
    testWidgets('课程课表：不抛布局异常，且星期表头 / 节次行 / 格子内容都真的画出来', (tester) async {
      final table = load('public_kckb_course.html', const ['课程']).single;
      expect(table.cells, isNotEmpty, reason: 'fixture 本身要能解析出格子');

      await pumpInScrollPage(tester, PublicTimetableCard(timetable: table));

      // 关键断言：曾经这里抛 `BoxConstraints forces an infinite height`
      expect(tester.takeException(), isNull);

      expect(find.byType(ExpansionTile), findsOneWidget);
      expect(find.text(table.owner), findsOneWidget);
      // 星期表头（只在展开体里，能画出来就说明网格真的布局了）
      expect(find.text('周一'), findsOneWidget);
      expect(find.text('周日'), findsOneWidget);
      // 节次行标签（每一行一个）
      for (final period in {
        for (final c in table.cells) c.periodIndex,
      }) {
        final first = table.cells.firstWhere((c) => c.periodIndex == period);
        expect(
          find.text(spanLabel(first)),
          findsWidgets,
          reason: '第 $period 个大节的行标签必须渲染',
        );
      }
      // 格子里的课程名（取 part 里第一个非纯数字段）
      expect(find.textContaining('管理学基础'), findsWidgets);
    });

    testWidgets('班级课表（5 格）：同样不得抛异常', (tester) async {
      final table = load('public_bjkb_class.html', const ['班级']).single;
      await pumpInScrollPage(tester, PublicTimetableCard(timetable: table));
      expect(tester.takeException(), isNull);
      expect(find.text('周一'), findsOneWidget);
      expect(find.textContaining('财务管理'), findsWidgets);
    });

    testWidgets('教室课表（多表）：一次渲染多张卡片也不得抛异常', (tester) async {
      final tables = load('public_jsikb_rooms.html', const ['教室']);
      expect(tables.length, greaterThan(1), reason: '教室 fixture 是多表');
      await pumpInScrollPage(
        tester,
        Column(
          children: [
            for (final t in tables)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PublicTimetableCard(timetable: t),
              ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ExpansionTile), findsNWidgets(tables.length));
    });

    testWidgets('空课表：显示「没有排课记录」而不是空白', (tester) async {
      const empty = PublicTimetable(fields: [], owner: '26会计学S9班', cells: []);
      await pumpInScrollPage(tester, const PublicTimetableCard(timetable: empty));
      expect(tester.takeException(), isNull);
      expect(find.text('该对象本学期没有排课记录。'), findsOneWidget);
    });
  });
}
