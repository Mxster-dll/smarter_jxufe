/// AA 算账 · 守卫（领域口径 + 存储 + 页面）。
///
/// 立项口径（用户 2026-09-19）：「我希望增加一个算账的工具，用于aa。我们可以手动
/// 添加一些开销，每个开销包括名称、金额、需要aa的人员；然后自动计算出每两个人之间
/// 的转钱情况」→ 本文件守三件事：**分毫不差的平分**、**最少笔数的转账**、
/// **页面能把这两件事讲清楚**。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/aa/data/aa_providers.dart';
import 'package:smarter_jxufe/features/aa/data/aa_store.dart';
import 'package:smarter_jxufe/features/aa/domain/aa_import.dart';
import 'package:smarter_jxufe/features/aa/domain/aa_models.dart';
import 'package:smarter_jxufe/features/aa/domain/aa_settlement.dart';
import 'package:smarter_jxufe/features/aa/presentation/aa_members_screen.dart';
import 'package:smarter_jxufe/features/aa/presentation/aa_screen.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_display_name_provider.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';

// ---- 构造帮手 ----

AaMember mm(String id, String name) => AaMember(id: id, name: name);

AaExpense ex({
  String id = 'e1',
  String title = '聚餐',
  double amount = 300,
  String payer = 'a',
  List<String> parts = const ['a', 'b', 'c'],
  DateTime? date,
}) => AaExpense(
  id: id,
  title: title,
  amount: amount,
  payerId: payer,
  participantIds: parts,
  date: date ?? DateTime(2026, 9, 19),
  createdAt: DateTime(2026, 9, 19, 12),
);

final List<AaMember> abc = [mm('a', '甲'), mm('b', '乙'), mm('c', '丙')];

/// 甲的净额（分）。
int netOf(AaSettlement s, String id) =>
    s.balances.firstWhere((b) => b.memberId == id).netCents;

// ---- Hive / provider 帮手 ----

late Directory _tmp;
var _boxSeq = 0;

/// 建一个空 box。
///
/// ⚠ **真实文件 I/O 必须包在 `tester.runAsync` 里**：`testWidgets` 的测试体跑在
/// 假异步区，`dart:io` 的 Future 在那里推不动 —— 直接 `await Hive.openBox(...)`
/// 会让测试永远不返回（实测 7 个 widget 测试全部 "did not complete" 并超时）。
Future<Box<String>> _newBox(WidgetTester tester) async {
  late Box<String> box;
  await tester.runAsync(() async {
    box = await Hive.openBox<String>('aa_test_${_boxSeq++}');
    await box.clear();
  });
  return box;
}

/// 纯 Dart 测试（不在假异步区）里用的 box。
Future<Box<String>> _syncBox() async {
  final box = await Hive.openBox<String>('aa_test_${_boxSeq++}');
  await box.clear();
  return box;
}

/// 预置数据：**真实写盘要在 `runAsync` 里做**（假异步区推不动文件 I/O）。
Future<void> _seed(
  WidgetTester tester,
  Box<String> box, {
  List<AaMember> members = const <AaMember>[],
  List<AaExpense> expenses = const <AaExpense>[],
}) async {
  await tester.runAsync(() async {
    await box.put(aaMembersKey, aaMembersJson(members));
    await box.put(aaExpensesKey, aaExpensesJson(expenses));
  });
}

/// 建容器并**先把数据读出来**再 pump：首帧就是数据帧，不依赖 `pumpAndSettle`
/// 去等异步（Hive 读是同步的内存读，只有写盘才是真 I/O）。
Future<ProviderContainer> _container(Box<String> box) async {
  final c = ProviderContainer(
    overrides: [aaStoreProvider.overrideWith((ref) async => AaStore(box))],
  );
  addTearDown(c.dispose);
  await c.read(aaDataProvider.future);
  return c;
}

Future<void> _pump(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: AaScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// 让**真 I/O**（Hive 写盘）跑完、再让 UI 追上。
///
/// `pumpAndSettle` 只推假时钟：文件写入的完成回调要靠真事件循环送达
/// （`runAsync`），之后假微任务队列才会被下一帧 flush 掉。
Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(() async {
    _tmp = await Directory.systemTemp.createTemp('aa_test_');
    Hive.init(_tmp.path);
  });

  tearDownAll(() async {
    // ⚠ 不调 `Hive.close()`：它在 widget 测试收尾阶段会**永远不返回**
    // （实测 tearDownAll "did not complete"）。临时目录由系统回收。
    if (_tmp.existsSync()) {
      try {
        _tmp.deleteSync(recursive: true);
      } catch (_) {
        // 文件被占用（Windows）删不掉不影响结论。
      }
    }
  });

  group('金额与日期', () {
    test('分 → 文案（含负数）', () {
      expect(aaMoney(0), '¥0.00');
      expect(aaMoney(100), '¥1.00');
      expect(aaMoney(1234), '¥12.34');
      expect(aaMoney(-1234), '-¥12.34');
      expect(aaMoney(5), '¥0.05');
    });

    test('元 → 分（浮点不收误差）', () {
      expect(aaCentsOf(33.34), 3334);
      expect(aaCentsOf(0.1 + 0.2), 30);
      expect(aaCentsOf(300), 30000);
    });

    test('日期只到天', () {
      expect(aaDateText(DateTime(2026, 9, 9)), '2026-09-09');
      expect(aaDay(DateTime(2026, 9, 9, 23, 59)), DateTime(2026, 9, 9));
    });

    test('取数容错：字符串数字 / 垃圾 / null', () {
      expect(aaNumOf('300'), 300);
      expect(aaNumOf('  12.5 '), 12.5);
      expect(aaNumOf('abc', fallback: -1), -1);
      expect(aaNumOf(null), 0);
      expect(aaStrOf(null, fallback: 'x'), 'x');
      expect(aaStrOf(12), '12');
    });

    test('参与人列表：非列表 → 空；去重去空白', () {
      expect(aaStrListOf('a'), isEmpty);
      expect(aaStrListOf(['a', 'a', ' b ', '', null]), ['a', 'b']);
    });
  });

  group('模型容错', () {
    test('成员：无 id 丢弃，空名字兜底', () {
      expect(AaMember.fromJson({'id': 'a', 'name': '甲'})!.name, '甲');
      expect(AaMember.fromJson({'id': 'a'}), mm('a', '未命名'));
      expect(AaMember.fromJson({'name': '甲'}), isNull);
      expect(AaMember.fromJson('甲'), isNull);
      expect(AaMember.fromJson(null), isNull);
    });

    test('成员：学号 / 班级（五轮加）容错 + 往返；老数据没有这两键 → 空串', () {
      final m = AaMember.fromJson({
        'id': 'a',
        'name': '甲',
        'studentNo': 2202500001,
        'className': '  25计算机2班 ',
      })!;
      expect(m.studentNo, '2202500001');
      expect(m.className, '25计算机2班');
      expect(m.detail, '2202500001 · 25计算机2班');

      // 老账本（只有 id/name）→ 不崩、不占位
      final old = AaMember.fromJson({'id': 'b', 'name': '乙'})!;
      expect(old.studentNo, '');
      expect(old.className, '');
      expect(old.detail, '');
      // 脏值（列表 / Map）→ 走 aaStrOf 变字符串，不抛
      expect(AaMember.fromJson({'id': 'c', 'name': '丙', 'studentNo': 5})!.studentNo, '5');

      // 整表往返：学号 / 班级不丢
      final back = aaMembersFromJson(aaMembersJson([m, old]));
      expect(back[0].studentNo, '2202500001');
      expect(back[0].className, '25计算机2班');
      expect(back[1].detail, '');
      // 空键不写进 JSON（老版本读新数据也不会看到多余字段）
      expect(aaMembersJson([old]), '[{"id":"b","name":"乙"}]');
    });

    test('开销：脏数据不崩（字符串金额 / 坏日期 / 非列表参与人）', () {
      final e = AaExpense.fromJson({
        'id': 'x',
        'title': '   ',
        'amount': '300',
        'payerId': 7,
        'participantIds': 'a,b',
        'date': '不是日期',
      })!;
      expect(e.title, '未命名开销');
      expect(e.amount, 300);
      expect(e.amountCents, 30000);
      expect(e.payerId, '7');
      expect(e.participantIds, isEmpty);
      expect(e.date, aaDay(DateTime.now()));
    });

    test('开销：金额 ≤ 0 / 非数 → 0（该笔不产生分摊）', () {
      expect(AaExpense.fromJson({'id': 'x', 'amount': -5})!.amount, 0);
      expect(AaExpense.fromJson({'id': 'x', 'amount': 'abc'})!.amount, 0);
      expect(AaExpense.fromJson({'id': 'x', 'amount': double.nan})!.amount, 0);
    });

    test('整表：坏 JSON → 空表；坏条目只丢自己', () {
      expect(aaMembersFromJson('不是 JSON'), isEmpty);
      expect(aaMembersFromJson('{"a":1}'), isEmpty);
      expect(aaExpensesFromJson('['), isEmpty);
      expect(aaExpensesFromJson('[{"id":"1"},5,{"no":"id"}]').length, 1);
    });

    test('往返无损（元 → JSON → 元，分不变）', () {
      final src = [ex(amount: 33.34), ex(id: 'e2', amount: 0.01)];
      final back = aaExpensesFromJson(aaExpensesJson(src));
      expect(back.length, 2);
      for (var i = 0; i < src.length; i++) {
        expect(back[i].id, src[i].id);
        expect(back[i].amountCents, src[i].amountCents);
        expect(back[i].payerId, src[i].payerId);
        expect(back[i].participantIds, src[i].participantIds);
        expect(back[i].date, src[i].date);
      }
    });

    test('排序：日期倒序 → 创建时刻倒序 → id 兜底', () {
      final list = [
        ex(id: 'b', date: DateTime(2026, 9, 18)),
        ex(id: 'a', date: DateTime(2026, 9, 19)),
        ex(id: 'c', date: DateTime(2026, 9, 18)),
      ];
      expect(aaSortedExpenses(list).map((e) => e.id).toList(), ['a', 'b', 'c']);
    });
  });

  group('平分口径', () {
    final known = <String>{'a', 'b', 'c'};

    test('除不尽 → 依次每人多 1 分，份额之和恒等于金额', () {
      final shares = aaSplitExpense(
        ex(amount: 100, parts: const ['a', 'b', 'c']),
        known: known,
      );
      expect(shares.map((s) => s.cents).toList(), [3334, 3333, 3333]);
      expect(shares.fold<int>(0, (a, s) => a + s.cents), 10000);
    });

    test('整除时人人相同', () {
      final shares = aaSplitExpense(
        ex(amount: 90, parts: const ['a', 'b', 'c']),
        known: known,
      );
      expect(shares.map((s) => s.cents).toList(), [3000, 3000, 3000]);
    });

    test('不含已知成员的参与人 → 直接出空（整笔不计）', () {
      expect(aaSplitExpense(ex(parts: const ['x', 'y']), known: known), isEmpty);
    });

    test('只按已知成员平分（成员被删后其余人重新平分）', () {
      final shares = aaSplitExpense(
        ex(amount: 100, parts: const ['a', 'b', 'x']),
        known: known,
      );
      expect(shares.map((s) => s.memberId).toList(), ['a', 'b']);
      expect(shares.fold<int>(0, (a, s) => a + s.cents), 10000);
    });

    test('金额为 0 → 空', () {
      expect(aaSplitExpense(ex(amount: 0), known: known), isEmpty);
    });
  });

  group('结算口径', () {
    test('一人垫付、三人 AA → 两条转账 + 净额', () {
      final s = aaSettle(members: abc, expenses: [ex(amount: 300)]);
      expect(s.totalCents, 30000);
      expect(s.expenseCount, 1);
      expect(netOf(s, 'a'), 20000);
      expect(netOf(s, 'b'), -10000);
      expect(netOf(s, 'c'), -10000);
      expect(s.transfers.map((t) => '${t.fromId}->${t.toId}:${t.cents}'), [
        'b->a:10000',
        'c->a:10000',
      ]);
    });

    test('两人互垫同额 → 已结清，零转账', () {
      final s = aaSettle(
        members: abc,
        expenses: [
          ex(id: 'e1', amount: 100, payer: 'a', parts: const ['a', 'b']),
          ex(id: 'e2', amount: 100, payer: 'b', parts: const ['a', 'b']),
        ],
      );
      expect(s.settled, isTrue);
      expect(s.transfers, isEmpty);
      expect(s.balances.every((b) => b.netCents == 0), isTrue);
    });

    test('多借多还 → 差额平账，笔数 = 债权 + 债务 − 1', () {
      final s = aaSettle(
        members: abc,
        expenses: [
          ex(id: 'e1', amount: 300, payer: 'a', parts: const ['a', 'b', 'c']),
          ex(id: 'e2', amount: 90, payer: 'b', parts: const ['b', 'c']),
        ],
      );
      // 甲 300−100=+200；乙 −100+45=−55；丙 −100−45=−145（两笔共 390 元）
      expect(netOf(s, 'a'), 20000);
      expect(netOf(s, 'b'), -5500);
      expect(netOf(s, 'c'), -14500);
      expect(s.totalCents, 39000);
      expect(s.transfers.length, 2);
      expect(s.transfers.map((t) => t.cents).reduce((a, b) => a + b), 20000);
      expect(s.settled, isFalse);
    });

    test('净额之和恒为 0（不变式）', () {
      final s = aaSettle(
        members: abc,
        expenses: [
          ex(id: 'e1', amount: 133.33, payer: 'a'),
          ex(id: 'e2', amount: 7.77, payer: 'c', parts: const ['b', 'c']),
          ex(id: 'e3', amount: 0.01, payer: 'b'),
        ],
      );
      expect(s.balances.fold<int>(0, (a, b) => a + b.netCents), 0);
      expect(
        s.balances.fold<int>(0, (a, b) => a + b.paidCents),
        s.totalCents,
      );
    });

    test('找不到付款人的开销整笔跳过（不凭空造欠款）', () {
      final s = aaSettle(
        members: abc,
        expenses: [ex(id: 'e1', payer: 'ghost'), ex(id: 'e2', amount: 60, payer: 'b', parts: const ['b', 'c'])],
      );
      expect(s.expenseCount, 1);
      expect(s.totalCents, 6000);
      expect(netOf(s, 'a'), 0);
    });

    test('没有成员 → 空结算', () {
      final s = aaSettle(members: const [], expenses: [ex()]);
      expect(s, same(AaSettlement.empty));
    });

    test('笔数统计：垫付笔数与分摊笔数', () {
      final s = aaSettle(
        members: abc,
        expenses: [
          ex(id: 'e1', amount: 300, payer: 'a', parts: const ['a', 'b', 'c']),
          ex(id: 'e2', amount: 60, payer: 'a', parts: const ['a', 'b']),
        ],
      );
      final a = s.balances.firstWhere((b) => b.memberId == 'a');
      final c = s.balances.firstWhere((b) => b.memberId == 'c');
      expect(a.paidCount, 2);
      expect(a.joinCount, 2);
      expect(c.paidCount, 0);
      expect(c.joinCount, 1);
    });

    test('同额时的确定性：按成员顺序优先', () {
      final net = {'x': -100, 'y': -100, 'z': 200};
      final out = aaSettleTransfers(order: const ['x', 'y', 'z'], netCents: net);
      expect(out.first.fromId, 'x');
      expect(out.last.fromId, 'y');
    });

    test('AaData：名字解析与已删除占位', () {
      final d = AaData.of(members: abc, expenses: [ex()]);
      expect(d.nameOf('a'), '甲');
      expect(d.nameOf('zzz'), '（已删除）');
      expect(d.settlement.expenseCount, 1);
      expect(d.settlement.creditors.single.memberId, 'a');
      expect(d.settlement.debtors.length, 2);
    });
  });

  group('存储', () {
    test('写入 → 读出（两张表各自往返）', () async {
      final box = await _syncBox();
      final store = AaStore(box);
      expect(await store.loadMembers(), isEmpty);
      expect(await store.loadExpenses(), isEmpty);

      await store.saveMembers(abc);
      await store.saveExpenses([ex(amount: 33.34)]);
      expect((await store.loadMembers()).map((m) => m.name).toList(), [
        '甲',
        '乙',
        '丙',
      ]);
      expect((await store.loadExpenses()).single.amountCents, 3334);
    });

    test('旧数据 / 脏数据 → 空表而不抛异常', () async {
      final box = await _syncBox();
      await box.put(aaMembersKey, '不是 JSON');
      await box.put(aaExpensesKey, '');
      final store = AaStore(box);
      expect(await store.loadMembers(), isEmpty);
      expect(await store.loadExpenses(), isEmpty);
    });
  });

  group('页面', () {
    testWidgets('空态：先加成员', (tester) async {
      final box = await _newBox(tester);
      final c = await _container(box);
      await _pump(tester, c);

      expect(find.text('AA 算账'), findsOneWidget);
      expect(find.textContaining('还没有成员'), findsOneWidget);
      expect(find.byKey(const Key('aaEmptyAddMember')), findsOneWidget);
      expect(find.byTooltip('添加开销'), findsOneWidget);
    });

    testWidgets('一笔 300 三人：两条转账 + 每人净额', (tester) async {
      final box = await _newBox(tester);
      await _seed(tester, box, members: abc, expenses: [ex(amount: 300)]);
      final c = await _container(box);
      await _pump(tester, c);

      expect(find.textContaining('共 1 笔'), findsOneWidget);
      expect(find.textContaining('¥300.00'), findsWidgets);
      expect(find.text('乙 → 甲'), findsOneWidget);
      expect(find.text('丙 → 甲'), findsOneWidget);
      expect(find.text('¥100.00'), findsNWidgets(2));
      expect(find.text('应收 ¥200.00'), findsOneWidget);
      expect(find.text('应付 ¥100.00'), findsNWidgets(2));
      expect(find.text('甲 垫付 · 3 人 AA · 2026-09-19'), findsOneWidget);
    });

    testWidgets('添加开销：默认全体参与，保存后进列表与结算', (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final box = await _newBox(tester);
      await _seed(tester, box, members: [mm('a', '甲'), mm('b', '乙')]);
      final c = await _container(box);
      await _pump(tester, c);

      await tester.tap(find.byTooltip('添加开销'));
      await tester.pumpAndSettle();
      expect(find.text('添加开销'), findsWidgets);

      await tester.enterText(find.byKey(const Key('aaTitleField')), '打车');
      await tester.enterText(find.byKey(const Key('aaAmountField')), '40');
      await tester.pumpAndSettle();
      expect(find.text('2 人平分 · 每人约 ¥20.00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('aaExpenseSave')));
      await tester.pumpAndSettle();
      await _settleIo(tester);

      expect(find.text('打车'), findsOneWidget);
      expect(find.text('乙 → 甲'), findsOneWidget);
      // 转账行是唯一的裸金额；净额行是「应收 ¥20.00」这种带前缀的整串。
      expect(find.text('¥20.00'), findsOneWidget);
      expect(find.text('应收 ¥20.00'), findsOneWidget);
      expect(find.text('应付 ¥20.00'), findsOneWidget);
      expect(find.textContaining('还没有开销'), findsNothing);
    });

    testWidgets('清空参与人 → 保存禁用；重选后恢复', (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final box = await _newBox(tester);
      await _seed(tester, box, members: [mm('a', '甲'), mm('b', '乙')]);
      final c = await _container(box);
      await _pump(tester, c);

      await tester.tap(find.byTooltip('添加开销'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('aaTitleField')), '打车');
      await tester.enterText(find.byKey(const Key('aaAmountField')), '40');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('aaPartNone')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('aaExpenseSave')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('aaPartAll')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('aaExpenseSave')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('成员页：添加成员 → 主页出现该成员', (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final box = await _newBox(tester);
      await _seed(tester, box, members: [mm('a', '甲')]);
      final c = await _container(box);
      await _pump(tester, c);

      await tester.tap(find.byTooltip('成员管理'));
      await tester.pumpAndSettle();
      expect(find.text('AA 成员'), findsOneWidget);

      await tester.tap(find.byKey(const Key('aaAddMember')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('aaMemberNameField')), '乙');
      // ⚠ 必须先 pump 一帧：`enterText` 只改控制器 + 标脏，不推帧；
      // 输入非空之前「保存」是禁用的（onPressed == null），此时 tap 会被吞掉。
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('aaMemberSave')));
      await tester.pumpAndSettle();
      await _settleIo(tester);

      expect(find.text('乙'), findsWidgets);
      expect(find.text('垫付 0 笔 · 分摊 0 笔'), findsNWidgets(2));

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('乙'), findsOneWidget);
    });

    testWidgets('成员页：垫付过的成员不许删', (tester) async {
      final box = await _newBox(tester);
      await _seed(
        tester,
        box,
        members: [mm('a', '甲'), mm('b', '乙')],
        expenses: [ex(amount: 100, payer: 'a', parts: const ['a', 'b'])],
      );
      final c = await _container(box);
      await _pump(tester, c);

      await tester.tap(find.byTooltip('成员管理'));
      await tester.pumpAndSettle();
      // 两位成员各有一个「删除」按钮 → 取第一位（甲，本笔的付款人）。
      await tester.tap(find.byTooltip('删除').first);
      await tester.pumpAndSettle();

      expect(find.text('无法删除'), findsOneWidget);
      expect(find.textContaining('垫付了 1 笔开销'), findsOneWidget);
      await tester.tap(find.byKey(const Key('aaCannotDeleteOk')));
      await tester.pumpAndSettle();
      expect(find.text('甲'), findsWidgets);
    });

    testWidgets('删掉唯一一笔开销 → 回到空账态', (tester) async {
      final box = await _newBox(tester);
      await _seed(tester, box, members: abc, expenses: [ex(amount: 300)]);
      final c = await _container(box);
      await _pump(tester, c);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('aaExpenseDeleteConfirm')));
      await tester.pumpAndSettle();
      await _settleIo(tester);

      expect(find.text('乙 → 甲'), findsNothing);
      expect(find.textContaining('还没有开销'), findsOneWidget);
      expect(find.text('聚餐'), findsNothing);
    });
  });

  // ---- 用户 2026-09-19 三轮：「允许添加自己」+「我们只要添加自己、添加室友、
  //      其他范围的同学不允许批量添加」----

  /// 建容器：成员表 + 数据中心名单 + 「我自己」（姓名 / 学号 / 班级）。
  ///
  /// 名单与「我自己」的**源** provider 直接 override（不打网络、不碰账号库 Hive），
  /// 走真实的 `aaSelfInfoProvider` / `aaImportMembers` 链路。
  Future<ProviderContainer> containerWithPeers(
    Box<String> box, {
    List<DzjPeer> peers = const <DzjPeer>[],
    List<DzjPeer> classmates = const <DzjPeer>[],
    bool classmatesError = false,
    String? error,
    String? selfName = '张三',
    String selfStudentNo = '2202500001',
    String selfClassName = '25计算机2班',
  }) async {
    final c = ProviderContainer(
      overrides: [
        aaStoreProvider.overrideWith((ref) async => AaStore(box)),
        dzjPeersProvider(aaRoommateDimension).overrideWith((ref) async {
          if (error != null) throw Exception(error);
          return peers;
        }),
        // 「补全学号 / 班级」还会读同班名单（`aaClassDimension`）：默认空，
        // 免得测试去打真网络 / 碰真 Hive。
        dzjPeersProvider(aaClassDimension).overrideWith((ref) async {
          if (classmatesError) throw Exception('同班名单读取失败');
          return classmates;
        }),
        // 「我自己」的真实实现 = 账号库显示名 + 学籍缓存（都走 Hive）；单测里直接给值，
        // 取值序本身另由 `aaStudentNoOf` 的用例覆盖。
        aaSelfInfoProvider.overrideWith(
          (ref) async => (
            name: selfName ?? '',
            studentNo: selfStudentNo,
            className: selfClassName,
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(aaDataProvider.future);
    return c;
  }

  Future<void> pumpMembers(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: AaMembersScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('添加自己 / 添加舍友', () {
    test('aaSelfInfoProvider：取账号显示名并去空白（学籍链读不到就留空）', () async {
      final c = ProviderContainer(
        overrides: [
          currentAccountNameProvider.overrideWith((ref) async => '  张三  '),
        ],
      );
      addTearDown(c.dispose);
      final me = await c.read(aaSelfInfoProvider.future);
      expect(me.name, '张三');
      // 学籍缓存里没有这条账号的数据 → 学号/班级留空，**不瞎猜**
      expect(me.studentNo, '');
      expect(me.className, '');
    });

    test('aaSelfInfoProvider：取不到 / 只有空白 / 读失败 → 姓名空串', () async {
      ProviderContainer of(String? Function() name) {
        final c = ProviderContainer(
          overrides: [
            currentAccountNameProvider.overrideWith((ref) async => name()),
          ],
        );
        addTearDown(c.dispose);
        return c;
      }

      expect((await of(() => null).read(aaSelfInfoProvider.future)).name, '');
      expect((await of(() => '   ').read(aaSelfInfoProvider.future)).name, '');
      expect(
        (await of(() => throw Exception('账号库读不到')).read(
          aaSelfInfoProvider.future,
        )).name,
        '',
      );
    });

    test('学号取值序：学籍 studentId → userId → 当前账号，只认 8 位以上纯数字', () {
      expect(
        aaStudentNoOf(studentId: '2202500001', userId: 'x', account: 'y'),
        '2202500001',
      );
      // studentId 是杂值（体测编号等）→ 退到 userId / 账号
      expect(
        aaStudentNoOf(studentId: '18', userId: '2202500004', account: 'y'),
        '2202500004',
      );
      expect(
        aaStudentNoOf(studentId: '', userId: '', account: '2202500002'),
        '2202500002',
      );
      // 全都不是学号形状 → 空串（宁可不显示，也不要写错）
      expect(
        aaStudentNoOf(studentId: 'abc', userId: '2025', account: ''),
        '',
      );
    });

    test('「添加我自己」文案两态 + 手填提示非空', () {
      expect(aaSelfImportMessage(name: '张三', added: true), '已添加你自己「张三」');
      expect(aaSelfImportMessage(name: '张三', added: false), '「张三」已在名单里');
      expect(aaSelfNameMissingHint.trim(), isNotEmpty);
    });

    test('按姓名去重：已有 / 空白 / 大小写 / 本批重复', () {
      var n = 0;
      final r = aaImportMembers(
        existing: [mm('a', '甲'), mm('b', '乙')],
        people: AaImportPerson.names(['甲', ' 丙 ', '丙', '', '   ', 'Ding', 'ding', '丁']),
        newId: () => 'new${n++}',
      );
      expect(
        [for (final m in r.members) m.name],
        ['甲', '乙', '丙', 'Ding', '丁'],
      );
      expect(r.added, 3);
      expect(r.skipped, 5);
      expect(r.changed, isTrue);
      // 原有成员对象原样保留（id 不变 → 已有开销的引用不断开）
      expect(r.members.first.id, 'a');
      expect(r.members[2].id, 'new0');
    });

    test('导入时把学号 / 班级一起带进账本（名单里本来就有这两列）', () {
      var n = 0;
      final r = aaImportMembers(
        existing: const [],
        people: const [
          AaImportPerson('李四', studentNo: '2202500004', className: '25计算机2班'),
          AaImportPerson('王五'),
        ],
        newId: () => 'new${n++}',
      );
      expect(r.members[0].studentNo, '2202500004');
      expect(r.members[0].className, '25计算机2班');
      expect(r.members[0].detail, '2202500004 · 25计算机2班');
      // 没给学号/班级 → 空串，界面不占位
      expect(r.members[1].detail, '');
      // 名单行 → 待导入的人（学号 = `ykth`/校园卡号，班级 = `ssbj`）
      final fromPeer = AaImportPerson.fromPeer(
        const DzjPeer(
          userId: '2202500002',
          name: '同学乙',
          className: '25计算机2班',
        ),
      );
      expect(fromPeer.name, '同学乙');
      expect(fromPeer.studentNo, '2202500002');
      expect(fromPeer.className, '25计算机2班');
    });

    test('summary 文案三态', () {
      expect(
        const AaImportResult(members: [], added: 3, skipped: 1).summary('舍友'),
        '已添加 3 位舍友（跳过 1 位已在名单里）',
      );
      expect(
        const AaImportResult(members: [], added: 2, skipped: 0).summary('舍友'),
        '已添加 2 位舍友',
      );
      expect(
        const AaImportResult(members: [], added: 0, skipped: 4).summary('舍友'),
        '没有新成员：舍友都已在名单里',
      );
      expect(
        const AaImportResult(members: [], added: 0, skipped: 0).summary('舍友'),
        '没有取到舍友',
      );
    });

    test('「添加全部舍友」= 我自己 + 舍友（自己在最前，学号班级一起带）', () {
      var n = 0;
      final r = aaImportRoommates(
        existing: [mm('a', '甲')],
        selfName: '  张三 ',
        selfStudentNo: '2202500001',
        selfClassName: '25计算机2班',
        roommates: const [
          AaImportPerson('李四', studentNo: '2202500004', className: '25计算机2班'),
          AaImportPerson('甲'),
          AaImportPerson('王五', studentNo: '2202500002', className: '25计算机2班'),
        ],
        newId: () => 'new${n++}',
      );
      // 顺序 = 已有成员 → 我自己 → 舍友名单顺序（默认付款人落在自己身上）
      expect(
        [for (final m in r.members) m.name],
        ['甲', '张三', '李四', '王五'],
      );
      expect(r.selfAdded, isTrue);
      expect(r.roommateAdded, 2);
      expect(r.roommateSkipped, 1);
      expect(r.changed, isTrue);
      // 已有成员对象原样保留（id 不变 → 已有开销的引用不断开）
      expect(r.members.first.id, 'a');
      expect(r.members[1].id, 'new0');
      expect(r.members[1].name, '张三');
      // 我自己与舍友的学号 / 班级都跟着进账本
      expect(r.members[1].detail, '2202500001 · 25计算机2班');
      expect(r.members[2].detail, '2202500004 · 25计算机2班');
      // 名单里没给的（`甲` 早就在账本里）不会被凭空补上学号
      expect(r.members[0].detail, '');
    });

    test('舍友导入文案：把「你自己」与舍友分开说', () {
      const both = AaRoommateImport(
        members: [],
        selfName: '张三',
        selfAdded: true,
        roommateAdded: 2,
        roommateSkipped: 0,
      );
      expect(both.summary, '已添加你自己 + 2 位舍友');

      const selfOnly = AaRoommateImport(
        members: [],
        selfName: '张三',
        selfAdded: true,
        roommateAdded: 0,
        roommateSkipped: 3,
      );
      expect(selfOnly.summary, '已添加你自己（3 位舍友已在名单里）');

      const none = AaRoommateImport(
        members: [],
        selfName: '张三',
        selfAdded: false,
        roommateAdded: 0,
        roommateSkipped: 3,
      );
      expect(none.summary, '没有新成员：你和舍友都已在名单里');
    });

    test('读不到自己姓名 → 只加舍友，提示里说明怎么补', () {
      var n = 0;
      final r = aaImportRoommates(
        existing: const [],
        selfName: '   ',
        roommates: const [AaImportPerson('李四')],
        newId: () => 'new${n++}',
      );
      expect(r.selfAdded, isFalse);
      expect([for (final m in r.members) m.name], ['李四']);
      expect(r.summary, '已添加 1 位舍友（$aaSelfNameMissingHint）');
    });

    test('舍友位次不会顶掉我自己：自己已在名单里就不重复加', () {
      var n = 0;
      final r = aaImportRoommates(
        existing: [mm('a', '张三'), mm('b', '李四')],
        selfName: '张三',
        roommates: const [AaImportPerson('李四'), AaImportPerson('王五')],
        newId: () => 'new${n++}',
      );
      expect(r.selfAdded, isFalse);
      expect(r.roommateAdded, 1);
      expect(r.roommateSkipped, 1);
      expect([for (final m in r.members) m.name], ['张三', '李四', '王五']);
      expect(r.summary, '已添加 1 位舍友（1 位舍友已在名单里）');
    });

    test('补全学号 / 班级：只补空字段、按姓名对上、id 与顺序不动', () {
      final old = [
        mm('a', '同学甲'), // 自己：姓名/学号/班级都能对上
        mm('b', '同学乙'), // 舍友：只有学号（舍友名单没有班级）
        mm('c', '同学丁').copyWith(studentNo: '手改过的'), // 已有值不许覆盖
        mm('d', '查无此人'),
      ];
      final r = aaBackfillMembers(
        existing: old,
        people: const [
          AaImportPerson('同学甲', studentNo: '2202500001', className: '计算机科学与技术252'),
          AaImportPerson('同学乙', studentNo: '2202500002'),
          AaImportPerson('同学丁', studentNo: '2202500004', className: '25计算机2班'),
        ],
      );
      expect(r.filled, 3);
      expect(r.changed, isTrue);
      expect(r.summary, '已补全 3 位成员的学号 / 班级');
      expect([for (final m in r.members) m.id], ['a', 'b', 'c', 'd']);
      expect(r.members[0].detail, '2202500001 · 计算机科学与技术252');
      expect(r.members[1].detail, '2202500002');
      // 手改过的学号保留，但缺的班级补上
      expect(r.members[2].detail, '手改过的 · 25计算机2班');
      // 名单里没有的人原样留着（不是删掉）
      expect(r.members[3].detail, '');
      expect(r.members[3].name, '查无此人');
    });

    test('补全：无可补 → filled=0；名字大小写 / 空白按同一把尺子对', () {
      final r = aaBackfillMembers(
        existing: [mm('a', '  ding ')],
        people: const [AaImportPerson('Ding', studentNo: '2202500004')],
      );
      expect(r.filled, 1, reason: '姓名去空白 + 忽略大小写后应能对上');
      expect(r.members.single.studentNo, '2202500004');

      final none = aaBackfillMembers(
        existing: [mm('a', '甲').copyWith(studentNo: '1', className: '2')],
        people: const [AaImportPerson('甲', studentNo: '9', className: '9')],
      );
      expect(none.changed, isFalse);
      expect(none.summary, '名单里没有能对上的学号 / 班级');
    });

    test('只允许批量导入舍友：其他维度没有入口、四选一弹层已删（源码守卫）', () {
      expect(aaRoommateDimension, DzjPeerDimension.dorm);
      // 「补全学号 / 班级」额外读同班名单，但**只读不落库**（不是批量添加入口）
      expect(aaClassDimension, DzjPeerDimension.classGroup);
      expect(
        File(
          'lib/features/aa/presentation/aa_peer_import_sheet.dart',
        ).existsSync(),
        isFalse,
        reason: '用户三轮口径：只留舍友，导入弹层不再需要',
      );

      // `features/aa/` 里允许出现的维度字面量**只有这两处常量**（都在 aa_import.dart）：
      // dorm = 可批量导入的舍友；classGroup = 补全班级用的只读对照表。
      // 同班 / 同专业 / 同学院 / 同年级依旧不给批量入口。
      // 模式按枚举实际取值拼（新加维度自动纳入，含方法名/类型名不算）。
      const allowed = {
        'DzjPeerDimension.dorm',
        'DzjPeerDimension.classGroup',
      };
      final pattern = RegExp(
        'DzjPeerDimension\\.(${DzjPeerDimension.values.map((d) => d.name).join('|')})\\b',
      );
      final offenders = <String>[];
      for (final f in Directory('lib/features/aa').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final isConstants = f.path
            .replaceAll(r'\', '/')
            .endsWith('domain/aa_import.dart');
        for (final m in pattern.allMatches(f.readAsStringSync())) {
          if (isConstants && allowed.contains(m.group(0))) continue;
          offenders.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(offenders, isEmpty, reason: 'AA 只允许这两种用途的名单：$offenders');
    });

    testWidgets('成员页 → 添加我自己 → 落库 + 提示', (tester) async {
      final box = await _newBox(tester);
      await _seed(tester, box, members: [mm('a', '甲')]);
      final c = await containerWithPeers(box);
      await pumpMembers(tester, c);
      expect(find.text('甲'), findsOneWidget);

      await tester.tap(find.byKey(const Key('aaAddSelf')));
      await tester.pumpAndSettle();
      await _settleIo(tester);

      expect(find.text('张三'), findsOneWidget);
      expect(find.textContaining('已添加你自己「张三」'), findsOneWidget);
      expect(aaMembersFromJson(box.get(aaMembersKey)!).length, 2);
    });

    testWidgets('自己已在名单里 → 不重复加、只提示', (tester) async {
      final box = await _newBox(tester);
      await _seed(tester, box, members: [mm('a', '张三')]);
      final c = await containerWithPeers(box);
      await pumpMembers(tester, c);

      await tester.tap(find.byKey(const Key('aaAddSelf')));
      await tester.pumpAndSettle();
      await _settleIo(tester);

      expect(find.textContaining('「张三」已在名单里'), findsOneWidget);
      expect(aaMembersFromJson(box.get(aaMembersKey)!).length, 1);
    });

    testWidgets('成员页 → 添加成员：可填学号 / 班级，落库并在行里显示', (tester) async {
      final box = await _newBox(tester);
      await _seed(tester, box);
      final c = await containerWithPeers(box);
      await pumpMembers(tester, c);

      await tester.tap(find.byKey(const Key('aaAddMember')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('aaMemberNameField')), '李四');
      await tester.enterText(find.byKey(const Key('aaMemberNoField')), '2202500004');
      await tester.enterText(
        find.byKey(const Key('aaMemberClassField')),
        '25计算机2班',
      );
      // ⚠ `enterText` 不推帧 → 此刻保存按钮还是禁用（onPressed == null），
      // tap 会被静默吞掉（弹层不关、库不动）。必须先 pump 一帧。
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('aaMemberSave')));
      await _settleIo(tester);

      final saved = aaMembersFromJson(box.get(aaMembersKey)!);
      expect(saved.single.name, '李四');
      expect(saved.single.studentNo, '2202500004');
      expect(saved.single.className, '25计算机2班');
      expect(find.text('2202500004 · 25计算机2班'), findsOneWidget);
    });

    testWidgets('成员页 → 编辑：学号 / 班级可改（手打成员事后补上）', (tester) async {
      final box = await _newBox(tester);
      await _seed(tester, box, members: [mm('a', '甲')]);
      final c = await containerWithPeers(box);
      await pumpMembers(tester, c);

      await tester.tap(find.byTooltip('编辑').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('aaMemberNoField')), '2202500001');
      await tester.enterText(
        find.byKey(const Key('aaMemberClassField')),
        '25计算机2班',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('aaMemberSave')));
      await _settleIo(tester);

      expect(aaMembersFromJson(box.get(aaMembersKey)!).single.detail,
          '2202500001 · 25计算机2班');
      expect(find.text('2202500001 · 25计算机2班'), findsOneWidget);
    });

    testWidgets('成员页 → 补全学号 / 班级（旧账本成员补标识，只补空字段）', (tester) async {
      final box = await _newBox(tester);
      await _seed(tester, box, members: [mm('a', '同学甲'), mm('b', '同学乙')]);
      final c = await containerWithPeers(
        box,
        // 「我自己」= 同学甲（账本里那位就是本人）
        selfName: '同学甲',
        peers: const [
          DzjPeer(userId: '2202500002', name: '同学乙'),
          DzjPeer(userId: '2202500003', name: '同学丙'),
        ],
        // 班级只在同班名单里（舍友名单只有学号/校区）
        classmates: const [
          DzjPeer(userId: '2202500002', name: '同学乙', className: '25计算机2班'),
        ],
      );
      await pumpMembers(tester, c);
      // 两人都还没有标识 → 出现补全按钮
      expect(find.byKey(const Key('aaBackfillMembers')), findsOneWidget);

      await tester.tap(find.byKey(const Key('aaBackfillMembers')));
      // 落库期间按钮挂转圈 → 同「添加全部舍友」，只能走 `_settleIo`
      await _settleIo(tester);

      final saved = aaMembersFromJson(box.get(aaMembersKey)!);
      expect(saved.length, 2);
      // 我自己来自学籍缓存（学号 + 班级），舍友来自舍友名单（学号）+ 同班名单（班级）
      expect(saved[0].detail, '2202500001 · 25计算机2班');
      expect(saved[1].detail, '2202500002 · 25计算机2班');
      expect(find.textContaining('已补全 2 位成员的学号 / 班级'), findsOneWidget);
      // 都补上了 → 按钮消失
      expect(find.byKey(const Key('aaBackfillMembers')), findsNothing);
    });

    testWidgets('补全：同班名单读不到也能补学号（不因一维失败整件事失败）', (tester) async {
      final box = await _newBox(tester);
      await _seed(tester, box, members: [mm('b', '同学乙')]);
      final c = await containerWithPeers(
        box,
        peers: const [DzjPeer(userId: '2202500002', name: '同学乙')],
        classmatesError: true,
      );
      await pumpMembers(tester, c);

      await tester.tap(find.byKey(const Key('aaBackfillMembers')));
      await _settleIo(tester);

      final saved = aaMembersFromJson(box.get(aaMembersKey)!);
      expect(saved.single.detail, '2202500002');
      expect(find.textContaining('已补全 1 位成员的学号 / 班级'), findsOneWidget);
    });

    testWidgets('读不到自己姓名 → 提示手填、不写库', (tester) async {
      final box = await _newBox(tester);
      await _seed(tester, box);
      final c = await containerWithPeers(box, selfName: null);
      await pumpMembers(tester, c);

      await tester.tap(find.byKey(const Key('aaAddSelf')));
      await tester.pumpAndSettle();
      await _settleIo(tester);

      expect(find.text(aaSelfNameMissingHint), findsOneWidget);
      expect(aaMembersFromJson(box.get(aaMembersKey)!).length, 0);
    });

    testWidgets('成员页 → 添加全部舍友 → 连我自己一起落库 + 提示（无维度选择这一步）', (
      tester,
    ) async {
      final box = await _newBox(tester);
      await _seed(tester, box, members: [mm('a', '甲')]);
      final c = await containerWithPeers(
        box,
        peers: const [
          DzjPeer(userId: '2202500004', name: '李四', className: '25计算机2班'),
          DzjPeer(userId: '2202500002', name: '王五', className: '25计算机2班'),
        ],
      );
      await pumpMembers(tester, c);
      expect(find.text('甲'), findsOneWidget);

      await tester.tap(find.byKey(const Key('aaImportRoommates')));
      // ⚠ 不能 `pumpAndSettle()`：落库期间按钮上挂着 `CircularProgressIndicator`
      // （永不停止的动画）→ 假异步区里写盘推不动、转圈永远不停 → 直接超时。
      // `_settleIo` 先开真异步窗口让 Hive 写完，再让 UI 追上。
      await _settleIo(tester);

      // 用户四轮口径：点「添加全部舍友」要把我自己也加进来
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('李四'), findsOneWidget);
      expect(find.text('王五'), findsOneWidget);
      expect(find.textContaining('已添加你自己 + 2 位舍友'), findsOneWidget);
      final saved = aaMembersFromJson(box.get(aaMembersKey)!);
      expect(saved.length, 4);
      expect(saved[1].name, '张三');
      // 五轮口径：学号 / 班级一起落库，并在成员行里显示出来
      expect(saved[1].detail, '2202500001 · 25计算机2班');
      expect(saved[2].detail, '2202500004 · 25计算机2班');
      expect(find.text('2202500004 · 25计算机2班'), findsOneWidget);
      // 其他范围的同学没有入口（用户三轮口径）
      expect(find.textContaining('同班同学'), findsNothing);
    });

    testWidgets('读不到自己姓名 → 舍友照加，提示里说明手填', (tester) async {
      final box = await _newBox(tester);
      await _seed(tester, box);
      final c = await containerWithPeers(
        box,
        peers: const [DzjPeer(userId: '2202500004', name: '李四')],
        selfName: null,
      );
      await pumpMembers(tester, c);

      await tester.tap(find.byKey(const Key('aaImportRoommates')));
      await _settleIo(tester);

      expect(find.text('李四'), findsOneWidget);
      expect(
        find.textContaining('已添加 1 位舍友（$aaSelfNameMissingHint）'),
        findsOneWidget,
      );
      expect(aaMembersFromJson(box.get(aaMembersKey)!).length, 1);
    });

    testWidgets('舍友都是已有成员、我自己也在 → 不写库、提示「没有新成员」', (tester) async {
      final box = await _newBox(tester);
      await _seed(tester, box, members: [mm('a', '张三'), mm('b', '甲')]);
      final c = await containerWithPeers(
        box,
        peers: const [DzjPeer(userId: '1', name: '甲')],
      );
      await pumpMembers(tester, c);

      await tester.tap(find.byKey(const Key('aaImportRoommates')));
      await tester.pumpAndSettle();
      await _settleIo(tester);

      expect(find.textContaining('没有新成员：你和舍友都已在名单里'), findsOneWidget);
      expect(aaMembersFromJson(box.get(aaMembersKey)!).length, 2);
    });

    testWidgets('名单读不到（未登录 / 会话失效）→ 提示失败、不写库、按钮可再点', (tester) async {
      final box = await _newBox(tester);
      await _seed(tester, box, members: [mm('a', '甲')]);
      final c = await containerWithPeers(
        box,
        error: '请先登录后再查看个人数据中心',
      );
      await pumpMembers(tester, c);

      await tester.tap(find.byKey(const Key('aaImportRoommates')));
      await tester.pumpAndSettle();

      expect(find.textContaining('读取名单失败'), findsOneWidget);
      expect(find.textContaining('请先登录后再查看个人数据中心'), findsOneWidget);
      expect(aaMembersFromJson(box.get(aaMembersKey)!).length, 1);
      // 忙标志已复位 → 按钮恢复可用（转圈不会永远停在那）
      final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('aaImportRoommates')),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}
