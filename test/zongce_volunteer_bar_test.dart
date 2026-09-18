import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_foreign.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';
import 'package:smarter_jxufe/features/zongce/presentation/widgets/volunteer_bar.dart';

/// 志愿服务时长进度条（表 18 档位分段）的守卫 —— 用户 2026-09-18：
/// 「志愿服务也基本和基本分、评议分、加权/体测成绩一样显示，唯一不同的是，
/// 还要额外在下方显示一个进度条，并根据各级别分段」；
/// 同日二轮（本文件的当前口径）：「志愿时长进度条太粗；进度条颜色不对；
/// 提示文本太多，『（按表 18 档位换算）』『24 h · 已得 4 分 · 距 30 h 还差 6 h
/// （可 +6 分）』都要去掉」→ 条 = 6 高 + 主题红 + **零说明文案**，
/// 组件内只留 6 组「门槛 + 分值」小字（12 个 Text）。
void main() {
  ThemeData barTheme() => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC3282E)),
  );

  Future<void> pumpBar(
    WidgetTester tester, {
    required double hours,
    List<(double, double)>? tiers,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: barTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              child: ZcVolunteerBar(
                hours: hours,
                tiers: tiers ?? zcVolunteerTiers,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  double fractionOf(WidgetTester tester, int i) => tester
      .widget<FractionallySizedBox>(
        find.descendant(
          of: find.byKey(Key('zcVolunteerSeg-$i')),
          matching: find.byType(FractionallySizedBox),
        ),
      )
      .widthFactor!;

  /// 第 [i] 段的填充色（`_Segment` 里内层那个 DecoratedBox）。
  Color fillOf(WidgetTester tester, int i) {
    final boxes = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byKey(Key('zcVolunteerSeg-$i')),
        matching: find.byType(DecoratedBox),
      ),
    );
    return (boxes.last.decoration as BoxDecoration).color!;
  }

  /// 第 [i] 段的轨道色（外层 DecoratedBox = `AppColors.tint` 淡底）。
  Color trackOf(WidgetTester tester, int i) {
    final boxes = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byKey(Key('zcVolunteerSeg-$i')),
        matching: find.byType(DecoratedBox),
      ),
    );
    return (boxes.first.decoration as BoxDecoration).color!;
  }

  group('条本身的形态（用户 2026-09-18 二轮：太粗 / 颜色不对 / 文案太多）', () {
    testWidgets('细条：高度 = zcVolunteerBarHeight（6），不是原来的 9', (tester) async {
      await pumpBar(tester, hours: 24);
      expect(zcVolunteerBarHeight, 6);
      expect(
        tester.getSize(find.byKey(const Key('zcVolunteerSeg-0'))).height,
        6,
      );
    });

    testWidgets('颜色 = 主题红（与该行胶囊同色），不是劳育青绿', (tester) async {
      await pumpBar(tester, hours: 24);
      final primary = barTheme().colorScheme.primary;
      expect(fillOf(tester, 0), primary, reason: '已达档 = 实心主题红');
      expect(fillOf(tester, 3), primary, reason: '段内填充同色');
      expect(
        trackOf(tester, 5),
        isNot(primary),
        reason: '未到的档只留淡底，不能也是实心红',
      );
    });

    testWidgets('零说明文案：只有 6 组「门槛 + 分值」小字（12 个 Text）', (tester) async {
      await pumpBar(tester, hours: 24);
      expect(find.byType(Text), findsNWidgets(12));
      expect(find.text('10h'), findsOneWidget);
      expect(find.text('10分'), findsOneWidget);
      for (final gone in const [
        '已得',
        '还差',
        '24 h',
        '24.0',
        '取值中',
        '已达最高档',
        '按表 18',
        '档位换算',
      ]) {
        expect(
          find.textContaining(gone),
          findsNothing,
          reason: '「$gone」这类提示文案已整体撤掉',
        );
      }
    });
  });

  group('分段口径（表 18：10/15/20/30/50/100 h → 1/2/4/6/8/10 分）', () {
    test('档位表就是规则表常量本身（不另抄一套），升序展示', () {
      expect(zcVolunteerTiers, [(100, 10), (50, 8), (30, 6), (20, 4), (15, 2), (10, 1)]);
    });

    testWidgets('6 段：段数 = 档位数', (tester) async {
      await pumpBar(tester, hours: 24);
      expect(find.byKey(const Key('zcVolunteerSeg-0')), findsOneWidget);
      expect(find.byKey(const Key('zcVolunteerSeg-5')), findsOneWidget);
      expect(find.byKey(const Key('zcVolunteerSeg-6')), findsNothing);
      // 段下两行 = 门槛 + 分值（6 段 × 2 行）
      expect(find.text('10h'), findsOneWidget);
      expect(find.text('100h'), findsOneWidget);
      expect(find.text('1分'), findsOneWidget);
      expect(find.text('10分'), findsOneWidget);
    });

    testWidgets('0 小时 → 六段全空', (tester) async {
      await pumpBar(tester, hours: 0);
      for (var i = 0; i < 6; i++) {
        expect(fractionOf(tester, i), 0, reason: '第 $i 段不该有进度');
      }
    });

    testWidgets('24 小时 → 10/15/20 三段满、30 那段 40%、其后为空', (tester) async {
      await pumpBar(tester, hours: 24);
      expect(fractionOf(tester, 0), 1);
      expect(fractionOf(tester, 1), 1);
      expect(fractionOf(tester, 2), 1);
      expect(fractionOf(tester, 3), closeTo(0.4, 1e-9), reason: '(24-20)/(30-20)');
      expect(fractionOf(tester, 4), 0);
      expect(fractionOf(tester, 5), 0);
    });

    testWidgets('恰好到线（10 h）→ 第一段满', (tester) async {
      await pumpBar(tester, hours: 10);
      expect(fractionOf(tester, 0), 1);
      expect(fractionOf(tester, 1), 0);
    });

    testWidgets('100 小时满档 → 六段全满；超出也全满', (tester) async {
      await pumpBar(tester, hours: 100);
      for (var i = 0; i < 6; i++) {
        expect(fractionOf(tester, i), 1);
      }

      await pumpBar(tester, hours: 150);
      for (var i = 0; i < 6; i++) {
        expect(fractionOf(tester, i), 1);
      }
    });

    testWidgets('小数小时：12.5 h → 第二段 (12.5-10)/5 = 半格', (tester) async {
      await pumpBar(tester, hours: 12.5);
      expect(fractionOf(tester, 0), 1);
      expect(fractionOf(tester, 1), closeTo(0.5, 1e-9));
    });

    testWidgets('自动源还在取值（hours = 0）→ 条照画、全空、无「取值中」文案', (tester) async {
      await pumpBar(tester, hours: 0);
      expect(find.byKey(const Key('zcVolunteerSeg-2')), findsOneWidget);
      expect(fractionOf(tester, 2), 0);
      expect(find.textContaining('取值中'), findsNothing);
    });

    testWidgets('注入自定义档位（边界用例）：单调递增的任意档位都能分段', (tester) async {
      await pumpBar(tester, hours: 3, tiers: [(1, 1), (4, 2)]);
      expect(find.byKey(const Key('zcVolunteerSeg-1')), findsOneWidget);
      expect(find.byKey(const Key('zcVolunteerSeg-2')), findsNothing);
      expect(fractionOf(tester, 0), 1);
      expect(fractionOf(tester, 1), closeTo(2 / 3, 1e-9), reason: '(3-1)/(4-1)');
    });
  });

  group('外语加分条目名 = 原文条目名（表 10）', () {
    test('填了原始成绩 → 取命中档位的原文条目名', () {
      expect(
        zcForeignEntryLabel(name: '大学英语四级', rawScore: 489),
        '大学英语四级 ≥425',
      );
      expect(
        zcForeignEntryLabel(name: '大学英语六级', rawScore: 500),
        '大学英语六级 ≥425',
      );
      expect(zcForeignEntryLabel(name: '雅思', rawScore: 6.5), '雅思 ≥6.5');
      expect(
        zcForeignEntryLabel(name: '雅思', rawScore: 6.0),
        '雅思 6 ≤ x < 6.5',
      );
      expect(zcForeignEntryLabel(name: 'GRE', rawScore: 320), 'GRE ≥320');
    });

    test('等级类证书：条目名就是证书名（无需填分）', () {
      expect(zcForeignEntryLabel(name: '日语 N1'), '日语 N1');
      expect(zcForeignEntryLabel(name: '英/日专业八级'), '英/日专业八级');
      expect(zcForeignEntryLabel(name: '韩语 TOPIK 六级'), '韩语 TOPIK 六级');
    });

    test('认不出 → null（行标题保持证书名）：目录外 / 没填分 / 未达门槛', () {
      expect(zcForeignEntryLabel(name: '其他证书', rawScore: 1.5), isNull);
      expect(zcForeignEntryLabel(name: '大学英语四级'), isNull);
      expect(zcForeignEntryLabel(name: '大学英语四级', rawScore: 400), isNull);
      expect(zcForeignEntryLabel(name: '', rawScore: 489), isNull);
    });

    test('名称容错沿用目录口径（空白 / 半角括号）', () {
      expect(
        zcForeignEntryLabel(name: '四六级(艺术体育类) 四级', rawScore: 425),
        '四六级（艺术体育类）四级 ≥425',
      );
    });

    test('材料库只显示原始成绩（不带综测的换算文案）', () {
      // 用户 2026-09-18：「材料库不是综测的材料库，因此里面的四级证书这样的，
      // 不需要显示『大学英语四级 489 → 1 分』而是直接显示『489』就可以了」。
      expect(zcForeignRawScoreText(489), '489');
      expect(zcForeignRawScoreText(489.0), '489');
      expect(zcForeignRawScoreText(6.5), '6.5');
      expect(zcForeignRawScoreText(4.25), '4.25');
      expect(zcForeignRawScoreText(null), '', reason: '等级类证书 / 没填分 → 不出胶囊');
      for (final v in const [489.0, 6.5]) {
        final raw = zcForeignRawScoreText(v);
        expect(raw, isNot(contains('→')));
        expect(raw, isNot(contains('大学英语四级')));
      }
    });
  });
}
