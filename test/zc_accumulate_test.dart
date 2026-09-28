import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';
import 'package:smarter_jxufe/features/zongce/presentation/zongce_widgets.dart';

/// 用户 2026-09-27：「我们希望增加一个综测开关『是否放开所有累加』的按钮，
/// 至于关于『是否放开所有累加』是怎么放开可以参考
/// `<参考材料目录>\JXUFE\2026综测\评优评先综测计算器.html` 与
/// `<参考材料目录>\JXUFE\2026综测\2026综测计算器.html` 在累加上的区别」
/// + 同日追加：「我希望你参考 `2026综测计算器.html` 给允许累加的项添加绿色胶囊」。
///
/// **口径（用户三问三答拍板）**：
/// 1. 开关位置 = 顶部学年选择器**同一行右侧**；
/// 2. 放开范围 = **只放开累加与封顶**（民主评议仍 ≤20、扣分项照旧、
///    等次评定与一票否决不变）；
/// 3. 绿色胶囊 = **静态常显**（按官方标准版固定挂在 9 个可累加分项上），
///    开关打开时另在维度标题上挂「本轮全部累加」总标记。
///
/// 参考文件在累加上的差别（`评优评先综测计算器.html` 的 `recalc()`）：
/// `const dAdd = num(sel("d-shi")) + dSx + dDuty + dHrP + dHrG;   /* 无 20 分封顶 */`
/// `const zAdd = zJS + zPaper + zWy + zCy;   /* 四类可累计，无 20 分封顶 */`
/// `const tAdd = tJS + tXL + num(sel("t-jt"));   /* 无 20 分封顶 */`
/// `mMt += mMtYuan;   /* 院级媒体不再限 10 分 */`、`dDuty/dHrP/dHrG` 全部「多项叠加」、
/// `calcJS` 的 `for (const it of arr) { total += it.v; }`（无 5 分封顶、不只计最高）。
ZcMaterial _m(
  String id,
  ZcTypeId type, {
  int level = 0,
  int opt = 0,
  double qty = 1,
  String cat = '',
  String name = '测试材料',
}) => ZcMaterial(
  id: id,
  typeId: type,
  name: name,
  dateIso: '2026-05-01',
  level: level,
  opt: opt,
  qty: qty,
  cat: cat,
);

/// 竞赛材料（需 `cat` 非空才计分）。
ZcMaterial _contest(String id, {String cat = 'c3', int level = 0, int opt = 2}) =>
    _m(id, ZcTypeId.contest, cat: cat, level: level, opt: opt);

/// 引擎明细里某个标签的值。
double _d(ZcCalcResult r, String label) {
  for (final d in r.details) {
    if (d.label == label) return d.value;
  }
  return 0;
}

/// 德育六个「附加分」板块的分槽值之和（含优秀事迹/贡献度/参与度/公共服务/荣誉两槽）。
double _moralSlots(ZcCalcResult r) =>
    _d(r, '德育 · 优秀事迹') +
    _d(r, '德育 · 思想教育贡献度') +
    _d(r, '德育 · 思想教育参与度') +
    _d(r, '德育 · 公共服务') +
    _d(r, '德育 · 荣誉称号（个人）') +
    _d(r, '德育 · 荣誉称号（集体）');

ZcCalcResult _calc(
  List<ZcMaterial> mats, {
  bool open = false,
  ZcManual manual = const ZcManual(),
}) => zcCalculate(
  mats,
  manual: manual.copyWith(openAccumulate: open),
  autoWeight: 80,
  autoVolunteer: 0,
);

String _src(String path) => File(path).readAsStringSync();

/// 剥掉整行注释后的源码（负面判据必须先剥注释 —— 说明性注释会引用旧写法）。
String _codeOnly(String src) =>
    src.split('\n').map((l) => l.split('//').first).join('\n');

void main() {
  group('放开累加 · 引擎：就高一次 → 多项叠加', () {
    test('优秀事迹（deed）：只取最高 → 全部相加', () {
      // deed level 0 = 国家级 5 分 / level 2 = 校级 3 分。
      final mats = [
        _m('a', ZcTypeId.deed, level: 0),
        _m('b', ZcTypeId.deed, level: 2),
      ];
      expect(_d(_calc(mats), '德育 · 优秀事迹'), 5);
      expect(_d(_calc(mats, open: true), '德育 · 优秀事迹'), 8);
    });

    test('思想教育 · 参与度（eduPart）：0.5 分/次，封顶 2 → 不封顶', () {
      final mats = [_m('a', ZcTypeId.eduPart, qty: 5)]; // 2.5 分
      expect(_d(_calc(mats), '德育 · 思想教育参与度'), 2);
      expect(_d(_calc(mats, open: true), '德育 · 思想教育参与度'), 2.5);
    });

    test('荣誉称号个人 + 集体：合计封顶 10 → 只受附加合计 20 约束', () {
      final mats = [
        _m('p', ZcTypeId.honorP, level: 0), // 10
        _m('g', ZcTypeId.honorG, level: 0), // 4
      ];
      // 两槽明细值不变（分槽值），差别只在父级封顶。
      final std = _calc(mats);
      expect(_d(std, '德育 · 荣誉称号（个人）'), 10);
      expect(_d(std, '德育 · 荣誉称号（集体）'), 4);
      expect(std.deyu, 70); // 60 + min(10+4, 10)
      expect(_calc(mats, open: true).deyu, 74); // 60 + 14
    });

    test('附加合计 20 分封顶 → 放开档 = 60 + 六板块之和（无封顶）', () {
      final mats = [
        _m('a', ZcTypeId.deed, level: 0), // 5
        _m('b', ZcTypeId.eduCon, level: 0), // 5
        _m('c', ZcTypeId.honorP, level: 0), // 10
        _m('d', ZcTypeId.honorG, level: 0), // 4
      ];
      final std = _calc(mats);
      final opn = _calc(mats, open: true);
      expect(_moralSlots(std), 24);
      expect(std.deyu, 80); // 60 + min(24, 20)
      expect(opn.deyu, 84); // 60 + 24
      // 不变量：放开档的德育分数 = 60 + 六个板块分槽值之和。
      expect(opn.deyu, 60 + _moralSlots(opn));
    });

    test('寝室（dorm，max 槽）：只取最高 → 全部相加', () {
      final mats = [
        _m('a', ZcTypeId.dorm, level: 0), // 标兵 10
        _m('b', ZcTypeId.dorm, level: 1), // 文明寝室 8
      ];
      expect(_calc(mats).laoyu, 70); // 60 + 10
      expect(_calc(mats, open: true).laoyu, 78); // 60 + 18
    });
  });

  group('放开累加 · 引擎：各自专项封顶取消', () {
    test('智育竞赛：累加封顶 5 / 只计最高 → 全部相加', () {
      // c3 国家级二等奖 = 3 分 ×3。
      final three = [
        _contest('a'),
        _contest('b'),
        _contest('c'),
      ];
      expect(_d(_calc(three), '智育 · 学科竞赛'), 5); // 3+3 ≥5 后截断
      expect(_d(_calc(three, open: true), '智育 · 学科竞赛'), 9);

      // 单条巨分（>5）标准档只计最高。
      final big = [_contest('a', cat: 'c1', level: 0, opt: 0), _contest('b')];
      expect(_d(_calc(big), '智育 · 学科竞赛'), 20);
      expect(_d(_calc(big, open: true), '智育 · 学科竞赛'), 23);
    });

    test('智育论文：国内一般 ≤1.5、合计 ≤5 → 全部相加', () {
      // gen = 0.5 分 × 作者序 1 → 4 条 = 2.0 分。
      final gen = [
        for (var i = 0; i < 4; i++) _m('g$i', ZcTypeId.paper, level: 5),
      ];
      expect(_d(_calc(gen), '智育 · 论文/专利'), 1.5);
      expect(_d(_calc(gen, open: true), '智育 · 论文/专利'), 2);

      // 专业相关专利发明 1 分 × 8 = 8 分（无破格 → 标准档封顶 5）。
      final pat = [
        for (var i = 0; i < 8; i++) _m('p$i', ZcTypeId.paper, level: 4),
      ];
      expect(_d(_calc(pat), '智育 · 论文/专利'), 5);
      expect(_d(_calc(pat, open: true), '智育 · 论文/专利'), 8);
    });

    test('智育附加合计 20 分封顶 → 放开档不封顶', () {
      final eight = [
        for (var i = 0; i < 8; i++) _m('p$i', ZcTypeId.paper, level: 4),
      ];
      // 标准档：论文合计封顶 5 → 附加 5 → 智育 80 + 5 = 85。
      expect(_calc(eight).zhiyu, 85);
      expect(_calc(eight, open: true).zhiyu, 88);
    });

    test('体育 / 美育 / 劳育：附加合计 20 分封顶 → 放开档不封顶', () {
      // 体育竞赛国家级破纪录 30 分。
      final sport = [_m('a', ZcTypeId.sportComp, level: 0, opt: 0)];
      expect(_calc(sport).tiyu, 80); // 60 + min(30, 20)
      expect(_calc(sport, open: true).tiyu, 90); // 60 + 30

      // 社会实践·优秀团队负责人 10 分 ×3 = 30 分。
      final social = [for (var i = 0; i < 3; i++) _m('s$i', ZcTypeId.social)];
      expect(_calc(social).laoyu, 80);
      expect(_calc(social, open: true).laoyu, 90);
    });

    test('美育：院级媒体合计 10 分封顶 → 放开档不封顶', () {
      // media level 4 = 院级 2 分 ×6 = 12 分（只受院级 10 分封顶约束）。
      final yuan = [
        for (var i = 0; i < 6; i++) _m('m$i', ZcTypeId.media, level: 4),
      ];
      expect(_d(_calc(yuan), '美育 · 文艺竞赛/媒体/活动'), 10);
      expect(_d(_calc(yuan, open: true), '美育 · 文艺竞赛/媒体/活动'), 12);
    });

    test('美育：非院级媒体 8 分 ×3 → 附加合计 20 封顶只在标准档', () {
      // level 1 = 国家级媒体 8 分（非院级，不受院级 10 分封顶约束）。
      final media = [
        for (var i = 0; i < 3; i++) _m('m$i', ZcTypeId.media, level: 1),
      ];
      expect(_calc(media).meiyu, 80); // 60 + min(24, 20)
      expect(_calc(media, open: true).meiyu, 84); // 60 + 24
    });
  });

  group('放开累加 · 引擎：刻意不放开的部分', () {
    test('民主评议两档都封顶 20', () {
      const manual = ZcManual(deyuPingyi: 30, meiyuPingyi: 30, laoyuPingyi: 30);
      final std = _calc(const [], manual: manual);
      final opn = _calc(const [], open: true, manual: manual);
      expect(_d(std, '德育 · 民主评议'), 20);
      expect(_d(opn, '德育 · 民主评议'), 20);
      expect(_d(opn, '美育 · 民主评议'), 20);
      expect(_d(opn, '劳育 · 民主评议'), 20);
      expect(std.deyu, opn.deyu);
      expect(std.meiyu, opn.meiyu);
      expect(std.laoyu, opn.laoyu);
    });

    test('扣分项照旧', () {
      const manual = ZcManual(kouQk: 1, tKou1: 1, mKou1: 3, lKou1: 2);
      final std = _calc(const [], manual: manual);
      final opn = _calc(const [], open: true, manual: manual);
      expect(_d(std, '德育 · 扣分'), -2);
      expect(_d(opn, '德育 · 扣分'), -2);
      expect(_d(opn, '体育 · 扣分'), -5);
      expect(_d(opn, '美育 · 扣分'), -3);
      expect(_d(opn, '劳育 · 扣分'), -2);
      expect(std.deyu, opn.deyu);
      expect(std.tiyu, opn.tiyu);
      expect(std.meiyu, opn.meiyu);
      expect(std.laoyu, opn.laoyu);
    });

    test('等次评定与一票否决照旧（放开档不改等次口径）', () {
      final mats = [for (var i = 0; i < 8; i++) _m('p$i', ZcTypeId.paper, level: 4)];
      // 一票否决：两档都判 fail。
      expect(_calc(mats, manual: const ZcManual(vetoD: true)).gD, ZcGrade.fail);
      expect(
        _calc(mats, open: true, manual: const ZcManual(vetoD: true)).gD,
        ZcGrade.fail,
      );
      // 同等材料下放开档分数更高，但等次仍按同一张表判（90+ = 优秀）。
      expect(_calc(const [], manual: const ZcManual(tScore: 95)).gT, ZcGrade.ok);
      expect(
        _calc(const [], open: true, manual: const ZcManual(tScore: 95)).gT,
        ZcGrade.ok,
      );
    });
  });

  group('放开累加 · 「计入 / 未计入」高亮口径跟着开关走', () {
    test('竞赛：标准档只高亮计入的几条，放开档全部计入', () {
      final three = [_contest('a'), _contest('b'), _contest('c')];
      expect(zcContestContributingIds(three), {'a', 'b'});
      expect(zcContestContributingIds(three, open: true), {'a', 'b', 'c'});
    });

    test('德育：标准档每槽就高，放开档六板块全部计入（且只认德育类型）', () {
      final mats = [
        _m('a', ZcTypeId.deed, level: 0),
        _m('b', ZcTypeId.deed, level: 2),
        _m('p', ZcTypeId.honorP, level: 0),
        _m('p2', ZcTypeId.honorP, level: 1),
        _contest('c'), // 非德育类型：两张表都不该收
      ];
      expect(zcMoralContributingIds(mats), {'a', 'p'});
      final all = zcMoralContributingIds(mats, open: true);
      expect(all, {'a', 'b', 'p', 'p2'});
      expect(all.contains('c'), isFalse);
    });
  });

  group('放开累加 · 开关落盘与目录口径', () {
    test('ZcManual.openAccumulate：默认关、往返保真、旧数据回落 false', () {
      expect(const ZcManual().openAccumulate, isFalse);
      const on = ZcManual(openAccumulate: true);
      expect(ZcManual.fromJson(on.toJson()).openAccumulate, isTrue);
      expect(on.toJson()['openAccumulate'], isTrue);
      // 旧数据没有这个键 → 标准档。
      expect(ZcManual.fromJson(const <String, dynamic>{}).openAccumulate, isFalse);
      expect(on.copyWith().openAccumulate, isTrue);
      expect(on.copyWith(openAccumulate: false).openAccumulate, isFalse);
    });

    test('「可累计」= agg 为 sum 或 paper，恰好 9 个类型（官方 9 处 .cum-badge）', () {
      expect(zcAggIsCumulative(ZcAgg.sum), isTrue);
      expect(zcAggIsCumulative(ZcAgg.paper), isTrue);
      expect(zcAggIsCumulative(ZcAgg.max), isFalse);
      expect(zcAggIsCumulative(ZcAgg.contest), isFalse);

      final ids = [
        for (final s in zcTypeSpecs)
          if (s.cumulative) s.id,
      ];
      expect(ids.toSet(), {
        ZcTypeId.eduPart, // d-3-2b 思想教育·参与度
        ZcTypeId.paper, // z-2-2 学术能力（论文/专利）
        ZcTypeId.sportComp, // t-2-1 体育竞赛
        ZcTypeId.psych, // t-2-2 心理健康活动
        ZcTypeId.artsComp, // m-3-1 文艺竞赛
        ZcTypeId.media, // m-3-2 媒体艺术
        ZcTypeId.artAct, // m-3-3 美育活动
        ZcTypeId.social, // l-3-2 社会实践
        ZcTypeId.laborAct, // l-3-3 劳育活动
      });
      expect(ids.length, 9);
      // 官方没给竞赛挂胶囊（标准版竞赛是「最高项 >5 只计最高，否则累加封顶 5」）。
      expect(zcTypeSpecOf[ZcTypeId.contest]!.cumulative, isFalse);
    });
  });

  group('界面：绿色胶囊与开关', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('zcCumChip：绿字 + 999 圆角 + 描边，文案「可累计」', (tester) async {
      await tester.pumpWidget(host(Builder(builder: (c) => zcCumChip(c))));
      expect(find.text('可累计'), findsOneWidget);
      final ctx = tester.element(find.text('可累计'));
      final box = tester.widget<Container>(
        find.ancestor(of: find.text('可累计'), matching: find.byType(Container)).first,
      );
      final deco = box.decoration! as BoxDecoration;
      expect(deco.borderRadius, BorderRadius.circular(999));
      expect(deco.border, isNotNull);
      expect(tester.widget<Text>(find.text('可累计')).style!.color,
          AppColors.success(ctx));
    });

    testWidgets('zcOpenAccumulateToggle：关 → 开，回调与图标/文字色都变', (tester) async {
      final taps = <bool>[];
      await tester.pumpWidget(host(Builder(
        builder: (c) => zcOpenAccumulateToggle(
          c,
          on: false,
          onChanged: taps.add,
        ),
      )));
      expect(find.byKey(const Key('zcOpenAccumulate')), findsOneWidget);
      expect(find.text('放开累加'), findsOneWidget);
      expect(find.byIcon(Icons.all_inclusive), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      await tester.tap(find.byKey(const Key('zcOpenAccumulate')));
      expect(taps, [true]);

      await tester.pumpWidget(host(Builder(
        builder: (c) => zcOpenAccumulateToggle(
          c,
          on: true,
          onChanged: taps.add,
        ),
      )));
      final ctx = tester.element(find.text('放开累加'));
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('放开累加')).style!.color,
        AppColors.success(ctx),
      );
    });

    testWidgets('zcCumBadge：关时原样返回原徽章；开时多挂「本轮全部累加」', (tester) async {
      await tester.pumpWidget(host(Builder(
        builder: (c) =>
            zcCumBadge(c, open: false, badge: const Text('+24')) ??
            const SizedBox.shrink(),
      )));
      expect(find.text('+24'), findsOneWidget);
      expect(find.text('本轮全部累加'), findsNothing);

      await tester.pumpWidget(host(Builder(
        builder: (c) =>
            zcCumBadge(c, open: true, badge: const Text('+24')) ??
            const SizedBox.shrink(),
      )));
      expect(find.text('+24'), findsOneWidget);
      expect(find.text('本轮全部累加'), findsOneWidget);

      await tester.pumpWidget(host(Builder(
        builder: (c) => zcCumBadge(c, open: true) ?? const SizedBox.shrink(),
      )));
      expect(find.text('本轮全部累加'), findsOneWidget);
    });

    testWidgets('zcOpenAccumulateNote：打开时给一行行内说明（不是 Tooltip）', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(Builder(builder: (c) => zcOpenAccumulateNote(c))),
      );
      expect(
        find.textContaining('已放开所有累加：所有「就高一次」改多项叠加'),
        findsOneWidget,
      );
      expect(find.textContaining('民主评议仍 ≤20'), findsOneWidget);
    });

    testWidgets('材料行：可累加类型挂胶囊，非累加类型不挂；分项标题已标时可关掉', (
      tester,
    ) async {
      // 思想教育 · 参与度（eduPart，agg = sum）→ 有胶囊。
      await tester.pumpWidget(host(Builder(
        builder: (c) => zcMatRow(c, _m('a', ZcTypeId.eduPart, qty: 4)),
      )));
      expect(find.text('可累计'), findsOneWidget);

      // 优秀事迹（deed，agg = max）→ 没有胶囊。
      await tester.pumpWidget(host(Builder(
        builder: (c) => zcMatRow(c, _m('a', ZcTypeId.deed, level: 0)),
      )));
      expect(find.text('可累计'), findsNothing);

      // `showCumulative: false`（分项标题已经标过）→ 行上不再重复挂。
      await tester.pumpWidget(host(Builder(
        builder: (c) => zcMatRow(
          c,
          _m('a', ZcTypeId.eduPart, qty: 4),
          showCumulative: false,
        ),
      )));
      expect(find.text('可累计'), findsNothing);
    });

    testWidgets('zcExtraItem：cumulative 时标题挂胶囊、材料行不重复挂（共 1 枚）', (
      tester,
    ) async {
      await tester.pumpWidget(host(Builder(
        builder: (c) => zcExtraItem(
          c,
          label: '思想教育 · 参与度（表 4）',
          value: 2,
          tipIds: const [],
          items: [_m('a', ZcTypeId.eduPart, qty: 4)],
          cumulative: true,
        ),
      )));
      expect(find.text('可累计'), findsOneWidget);

      await tester.pumpWidget(host(Builder(
        builder: (c) => zcExtraItem(
          c,
          label: '优秀事迹（表 3）',
          value: 5,
          tipIds: const [],
          items: [_m('a', ZcTypeId.deed, level: 0)],
        ),
      )));
      expect(find.text('可累计'), findsNothing);
    });
  });

  group('源码守卫：唯一实现与接线', () {
    final engine = _src('lib/features/zongce/domain/zc_engine.dart');
    final catalog = _src('lib/features/zongce/domain/zc_catalog.dart');
    final widgets = _src('lib/features/zongce/presentation/zongce_widgets.dart');
    final screen = _src('lib/features/zongce/presentation/zongce_screen.dart');

    test('开关口径住在 ZcManual + 引擎只认 manual.openAccumulate', () {
      expect(engine, contains('final open = manual.openAccumulate;'));
      // 标准档 8 处「就高一次」全部改走 slotBest，裸 slotMax 只剩定义与 slotBest 自身。
      final bare = [
        for (final l in _codeOnly(engine).split('\n'))
          if (l.contains('slotMax(')) l.trim(),
      ];
      expect(bare.length, 2, reason: bare.join(' | '));
      expect(bare.last, contains('double slotBest(ZcTypeId id)'));
      // 8 处附加分封顶全部改走 capped（+ 1 行定义）。
      final caps = [
        for (final l in _codeOnly(engine).split('\n'))
          if (l.contains('capped(')) l.trim(),
      ];
      expect(caps.length, 9, reason: caps.join(' | '));
      // 民主评议刻意保持 _c(..., 0, 20)。
      expect(engine, contains('_c(manual.deyuPingyi, 0, 20)'));
      expect(engine, contains('_c(manual.meiyuPingyi, 0, 20)'));
      expect(engine, contains('_c(manual.laoyuPingyi, 0, 20)'));
    });

    test('「可累计」判据只有一处实现（catalog），且胶囊唯一实现在 widgets', () {
      var defs = 0;
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.contains('${Platform.pathSeparator}old${Platform.pathSeparator}')) {
          continue;
        }
        final t = f.readAsStringSync();
        if (t.contains('bool zcAggIsCumulative(')) defs++;
      }
      expect(defs, 1);
      expect(catalog, contains('bool zcAggIsCumulative(ZcAgg agg) =>'));
      expect(widgets, contains('Widget zcCumChip(BuildContext context'));
      // 胶囊只此一处：别处不许再自拼「可累计」文案。
      final hits = [
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File && f.path.endsWith('.dart'))
            if (_codeOnly(f.readAsStringSync()).contains("'可累计'"))
              f.path.replaceAll('\\', '/'),
      ];
      expect(hits, ['lib/features/zongce/presentation/zongce_widgets.dart']);
    });

    test('页面接线：开关 + 五处总标记 + 高亮传 open', () {
      expect(widgets, contains("key: const Key('zcOpenAccumulate')"));
      expect(widgets, contains('Widget zcOpenAccumulateNote('));
      expect(screen, contains('zcOpenAccumulateNote(context)'));
      // 本仓 2026-09-18 四轮裁定：页面不留纯文字悬停（开关语义走行内说明）。
      expect(widgets.contains('Tooltip('), isFalse);
      expect(screen.contains('Tooltip('), isFalse);
      expect(screen.contains('_buildOpenAccumulateToggle'), isFalse);
      expect(screen, contains('zcOpenAccumulateToggle('));
      expect(screen, contains('open: _manual.openAccumulate,'));
      expect(screen, contains('copyWith(openAccumulate: v)'));
      final code = _codeOnly(screen);
      expect(code.split('zcCumBadge(').length - 1, 5);
      expect(code, contains('zcMoralContributingIds(\n      dMats,\n      open:'));
      expect(code, contains('zcContestContributingIds(\n      contestItems,\n      open:'));
      // 两个「分项级」胶囊：参与度（表 4）与论文/专利（表 9）。
      expect(code.split('cumulative: true,').length - 1, 2);
      expect(screen, contains('? \'加分项 · 四类全部累加（不设上限）\''));
      expect(screen, contains('_addMeta('));
      // 只有「写了封顶数字」的两张卡（智育 / 体育）走 `_addMeta`：定义 1 + 调用 2。
      expect(_codeOnly(screen).split('_addMeta(').length - 1, 3);
    });

    test('AI 工具也吃同一个开关（计入/未计入不能自相矛盾）', () {
      final ai = _src('lib/features/ai/tools/life_tools.dart');
      expect(ai, contains('_zongceMaterialLines(mats, open: manual.openAccumulate)'));
      expect(ai, contains('zcContestContributingIds(mats, open: open)'));
      expect(ai, contains('zcMoralContributingIds(mats, open: open)'));
    });
  });
}
