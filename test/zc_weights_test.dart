import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/status_palette.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_weights.dart';
import 'package:smarter_jxufe/features/zongce/presentation/widgets/weight_sheet.dart';
import 'package:smarter_jxufe/features/zongce/presentation/zongce_widgets.dart';
import 'package:smarter_jxufe/shared/widgets/academic_year_picker.dart';

/// 总评成绩（五育加权）的守卫 —— 用户 2026-09-18：
/// 「综测不是直接算平均分，而是有一个总评成绩，这个成绩的占比由班主任定，
/// 应该让用户自行设置」。
///
/// 三条拍板：① 默认占比 `20 / 35 / 15 / 15 / 15`；② 入口 = 综测页「总评成绩」
/// 那一行的胶囊就地弹层；③ **按学年各存一套**（挂在 `ZcManual` 里）。
void main() {
  group('ZcWeights 取值与容错', () {
    test('默认档 = 用户拍板的 20/35/15/15/15，合计 100', () {
      expect(ZcWeights.initial.values, [20, 35, 15, 15, 15]);
      expect(ZcWeights.initial.sum, 100);
      expect(ZcWeights.initial.isValid, isTrue);
      expect(ZcWeights.initial.label, '20 / 35 / 15 / 15 / 15');
      expect(ZcWeights.initial.isEven, isFalse);
    });

    test('等权档各 20%（= 旧的五育平均口径）', () {
      expect(ZcWeights.even.values, [20, 20, 20, 20, 20]);
      expect(ZcWeights.even.isEven, isTrue);
      expect(ZcWeights.even.isValid, isTrue);
    });

    test('合计校验：100 ± 0.5 之外都不合法', () {
      expect(const ZcWeights(d: 20, z: 35, t: 15, m: 15, l: 15.5).isValid, isTrue);
      expect(const ZcWeights(d: 20, z: 35, t: 15, m: 15, l: 16).isValid, isFalse);
      expect(const ZcWeights(d: 20, z: 20, t: 20, m: 20, l: 19.5).isValid, isTrue);
      expect(const ZcWeights(d: 20, z: 20, t: 20, m: 20, l: 18).isValid, isFalse);
    });

    test('总评 = Σ 五育 × 占比 / 100', () {
      const w = ZcWeights(d: 20, z: 35, t: 15, m: 15, l: 15);
      final total = w.applyTo(
        deyu: 90,
        zhiyu: 80,
        tiyu: 70,
        meiyu: 60,
        laoyu: 50,
      );
      // 90×20 + 80×35 + 70×15 + 60×15 + 50×15 = 1800+2800+1050+900+750 = 7300
      expect(total, closeTo(73.0, 1e-9));
      // 等权档就等于五育平均
      const even = ZcWeights.even;
      expect(
        even.applyTo(deyu: 90, zhiyu: 80, tiyu: 70, meiyu: 60, laoyu: 50),
        closeTo((90 + 80 + 70 + 60 + 50) / 5, 1e-9),
      );
    });

    test('百分数文案：整数不带小数点、小数最多一位', () {
      expect(zcWeightPercentText(20), '20');
      expect(zcWeightPercentText(12.5), '12.5');
      expect(zcWeightPercentText(12.4999), '12.5');
      expect(zcWeightPercentText(0), '0');
    });

    test('JSON 容错：非 Map / 字段非数 / 合计不是 100 → 回落默认档', () {
      expect(ZcWeights.fromJson(null), ZcWeights.initial);
      expect(ZcWeights.fromJson('nope'), ZcWeights.initial);
      expect(ZcWeights.fromJson({'d': 1, 'z': 2}), ZcWeights.initial);
      // 脏数据是字符串 → 不抛异常（本仓库踩过 `as num?` 的坑）
      expect(
        ZcWeights.fromJson({'d': '20', 'z': 35, 't': 15, 'm': 15, 'l': 15}),
        ZcWeights.initial,
      );
      // 合计 90 → 不合法 → 默认档
      expect(
        ZcWeights.fromJson({'d': 20, 'z': 20, 't': 20, 'm': 20, 'l': 10}),
        ZcWeights.initial,
      );
      // 越界值先 clamp 再校验
      expect(
        ZcWeights.fromJson({'d': 120, 'z': -20, 't': 0, 'm': 0, 'l': 0}),
        ZcWeights.initial,
      );
      expect(
        ZcWeights.fromJson({'d': 25, 'z': 25, 't': 25, 'm': 25, 'l': 0}),
        const ZcWeights(d: 25, z: 25, t: 25, m: 25, l: 0),
      );
    });
  });

  group('按学年各存一套（挂在 ZcManual 里）', () {
    test('ZcManual JSON 往返保留占比', () {
      const man = ZcManual(weights: ZcWeights(d: 10, z: 40, t: 20, m: 20, l: 10));
      final back = ZcManual.fromJson(
        jsonDecode(jsonEncode(man.toJson())) as Map<String, dynamic>,
      );
      expect(back.weights, const ZcWeights(d: 10, z: 40, t: 20, m: 20, l: 10));
    });

    test('旧数据（没有 weights 键）→ 默认档，不崩', () {
      final legacy = ZcManual.fromJson(const {'deyuPingyi': 12, 'tScore': 77});
      expect(legacy.weights, ZcWeights.initial);
      expect(legacy.deyuPingyi, 12);
    });

    test('copyWith 只换占比、其余字段不动', () {
      const man = ZcManual(deyuPingyi: 9, tScore: 81);
      final next = man.copyWith(weights: ZcWeights.even);
      expect(next.weights, ZcWeights.even);
      expect(next.deyuPingyi, 9);
      expect(next.tScore, 81);
      expect(man.weights, ZcWeights.initial, reason: '原对象不可变');
    });
  });

  group('引擎：总评成绩 = 五育加权', () {
    test('默认占比下总评 = 各育 × 20/35/15/15/15', () {
      final r = zcCalculate(const [], manual: const ZcManual(), autoWeight: 80);
      final expectTotal =
          (r.deyu * 20 + r.zhiyu * 35 + r.tiyu * 15 + r.meiyu * 15 + r.laoyu * 15) /
          100;
      expect(r.total, closeTo(expectTotal, 0.005));
      expect(r.weights, ZcWeights.initial);
      // 总评 ≠ 五育平均（默认档就不是等权）
      expect(r.total, isNot(closeTo(r.average, 0.01)));
    });

    test('换成等权档 → 总评 == 五育平均（且与旧口径逐值一致）', () {
      const man = ZcManual(weights: ZcWeights.even, laoyuPingyi: 20);
      final r = zcCalculate(const [], manual: man, autoWeight: 80);
      expect(r.total, closeTo(r.average, 0.005));
      expect(r.average, (r.deyu + r.zhiyu + r.tiyu + r.meiyu + r.laoyu) / 5);
    });

    test('提高德育占比 → 德育高的方案总评更高（占比真的参与计算）', () {
      final base = zcCalculate(
        const [],
        manual: const ZcManual(deyuPingyi: 20, tScore: 60),
        autoWeight: 60,
      );
      final dHeavy = zcCalculate(
        const [],
        manual: const ZcManual(
          deyuPingyi: 20,
          tScore: 60,
          weights: ZcWeights(d: 80, z: 5, t: 5, m: 5, l: 5),
        ),
        autoWeight: 60,
      );
      expect(base.deyu, greaterThan(base.zhiyu));
      expect(dHeavy.total, greaterThan(base.total));
    });

    test('总评保留 2 位小数（与加权/智育同精度）', () {
      final r = zcCalculate(const [], manual: const ZcManual(), autoWeight: 91.85965);
      expect(r.total, closeTo((r.total * 100).roundToDouble() / 100, 1e-9));
    });

    test('ZcCalcResult.average 仍在（只是降级为对照值）', () {
      final r = zcCalculate(const [], manual: const ZcManual(), autoWeight: 80);
      expect(r.average, (r.deyu + r.zhiyu + r.tiyu + r.meiyu + r.laoyu) / 5);
    });
  });

  group('占比弹层（入口 = 总评胶囊）', () {
    Future<ZcWeights?> openSheet(
      WidgetTester tester, {
      required ZcWeights weights,
      required Future<void> Function(WidgetTester) interact,
    }) async {
      ZcWeights? out;
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async {
                    opened = true;
                    out = await showZcWeightSheet(context, weights: weights);
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
      expect(opened, isTrue);
      await interact(tester);
      return out;
    }

    Future<void> setField(WidgetTester tester, String key, String text) async {
      await tester.enterText(find.byKey(Key('zcWeightField-$key')), text);
      await tester.pump();
    }

    testWidgets('五个输入框按当前占比预填、合计 100% 时保存可用', (tester) async {
      await openSheet(
        tester,
        weights: const ZcWeights(d: 10, z: 40, t: 20, m: 20, l: 10),
        interact: (tester) async {
          String text(String k) => tester
              .widget<TextField>(find.byKey(Key('zcWeightField-$k')))
              .controller!
              .text;
          expect(text('d'), '10');
          expect(text('z'), '40');
          expect(text('t'), '20');
          expect(text('m'), '20');
          expect(text('l'), '10');
          expect(
            tester.widget<Text>(find.byKey(const Key('zcWeightTotal'))).data,
            '合计 100%',
          );
          expect(
            tester
                .widget<FilledButton>(find.byKey(const Key('zcWeightSave')))
                .onPressed,
            isNotNull,
          );
          await tester.tap(find.byKey(const Key('zcWeightCancel')));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('合计 ≠ 100 → 红字提示且保存禁用；改回 100 恢复', (tester) async {
      final out = await openSheet(
        tester,
        weights: ZcWeights.initial,
        interact: (tester) async {
          await setField(tester, 'l', '30'); // 合计 115
          expect(
            tester.widget<Text>(find.byKey(const Key('zcWeightTotal'))).data,
            '合计 115%',
          );
          expect(
            tester
                .widget<FilledButton>(find.byKey(const Key('zcWeightSave')))
                .onPressed,
            isNull,
            reason: '合计不是 100% 不许保存',
          );
          await setField(tester, 'l', '15');
          expect(
            tester
                .widget<FilledButton>(find.byKey(const Key('zcWeightSave')))
                .onPressed,
            isNotNull,
          );
          await tester.tap(find.byKey(const Key('zcWeightSave')));
          await tester.pumpAndSettle();
        },
      );
      expect(out, ZcWeights.initial);
    });

    testWidgets('清空某格 → 合计显示 — 且保存禁用；预设「各 20%」一键填平', (tester) async {
      final out = await openSheet(
        tester,
        weights: ZcWeights.initial,
        interact: (tester) async {
          await setField(tester, 'z', '');
          expect(
            tester.widget<Text>(find.byKey(const Key('zcWeightTotal'))).data,
            '合计 —',
          );
          expect(
            tester
                .widget<FilledButton>(find.byKey(const Key('zcWeightSave')))
                .onPressed,
            isNull,
          );
          await tester.tap(find.byKey(const Key('zcWeightPreset-even')));
          await tester.pump();
          expect(
            tester
                .widget<TextField>(find.byKey(const Key('zcWeightField-z')))
                .controller!
                .text,
            '20',
          );
          await tester.tap(find.byKey(const Key('zcWeightSave')));
          await tester.pumpAndSettle();
        },
      );
      expect(out, ZcWeights.even);
    });
  });

  group('源码守卫', () {
    final screen = _zcSrc();

    test('总评成绩 = 可点数值（二轮起不是胶囊），点它打开占比弹层', () {
      expect(screen, contains("Key('zcTotalChip')"));
      expect(screen, contains("'总评成绩'"));
      expect(screen, contains('_editWeights(r.weights)'));
      expect(screen, contains('showZcWeightSheet(context, weights: current)'));
      expect(
        screen.contains('_manual.copyWith(weights: next)'),
        isTrue,
        reason: '弹层结果必须写回按学年落盘的 ZcManual',
      );
      // 用户 2026-09-21 二轮：「总评成绩不要显示为胶囊」+「不显示铅笔图标」。
      final code = screen
          .split('\n')
          .map((line) => line.split('//').first)
          .join('\n');
      expect(code, contains('pill: false'), reason: '头部那栏不再画胶囊底');
      expect(code, contains('showPencil: false'), reason: '不再画铅笔提示');
      // 界面层不许再自己算平均当总评
      expect(
        screen.contains('(r.deyu + r.zhiyu + r.tiyu + r.meiyu + r.laoyu) / 5'),
        isFalse,
        reason: '平均分只是对照值，总评一律取引擎的 r.total',
      );
      expect(screen, contains('r.total'));
    });

    test('结果卡头部 = 总评成绩，占比挪到每育名称后（用户 2026-09-21）', () {
      // 用户原话：「我希望综测顶部汇总卡片不要显示：占比 20 / 35 / 15 / 15 / 15、
      // 加权成绩 91.86 分、材料条数 13 条 这些信息，而是把占比显示到每个"育"的
      // 名称后面」+「"测评结果"改成"总评成绩"，右侧显示总评成绩」+「去除
      // "填写/录入后自动计算，实时更新"」。
      expect(screen, contains("Key('zcTotalChip')"), reason: '总评成绩移到头部右侧');
      expect(
        screen,
        contains('large: true'),
        reason: '头部那枚是大号可点数值（二轮起去掉胶囊壳，仍是 19px 大字）',
      );
      expect(screen, contains("'总评成绩'"));
      // ⚠ 判「旧文案是否还在」要**剥掉注释**再比：本轮新增的说明性注释里逐字引用了
      // 用户原话（含「测评结果」「材料条数」），直接 contains 会把注释判成违规。
      final code = screen
          .split('\n')
          .map((line) => line.split('//').first)
          .join('\n');
      expect(code.contains('测评结果'), isFalse, reason: '标题已改名');
      expect(
        code.contains('填写/录入后自动计算，实时更新'),
        isFalse,
        reason: '副标题整条删掉',
      );
      expect(code.contains('材料条数'), isFalse, reason: '材料条数那行不再显示');
      expect(
        code.contains('zcStatLine('),
        isFalse,
        reason: '加权成绩 / 材料条数两行是 zcStatLine 唯一用途，函数已删',
      );
      expect(
        code.contains("Key('zcTotalWeightsLabel')"),
        isFalse,
        reason: '「占比 20 / 35 / 15 / 15 / 15」那行已删',
      );
      expect(
        code,
        contains(r"'${zcWeightPercentText(it.$4)}%'"),
        reason: '占比改成每育名称后的小胶囊（第 4 项 = 该育占比）',
      );
      // 四轮更正（用户 2026-09-27：「每板块的占比胶囊不要有颜色，就用默认；
      // 各育的名字也不要有颜色，就默认颜色」）→ 育名不带 color、占比胶囊走中性灰；
      // 分数与行尾等次小胶囊仍是等次色（2026-09-21 三轮口径未变）。
      expect(
        code.contains(r'it.$5'),
        isFalse,
        reason: '育名 / 占比都不再取该育色（rows 的第 5 项已删）',
      );
      expect(
        code,
        contains('color: AppColors.tint(context, scheme.outline, 0.12)'),
        reason: '占比胶囊底色改回中性灰',
      );
      expect(
        code,
        contains('color: scheme.outline'),
        reason: '占比胶囊文字也走中性灰',
      );
      expect(
        code,
        contains(r'TextStyle(fontSize: 12.5)'),
        reason: '育名 = 默认文字色（不带 color）',
      );
      expect(
        code,
        contains(r'color: zcGradeColor(context, it.$3)'),
        reason: '分数按该育等次上色',
      );
      expect(code, contains('it.\$3.label'), reason: '行尾等次小胶囊保留');
    });

    test('学年切换 = 共享学年选择器（旧的两个箭头按钮已撤）', () {
      expect(screen, contains('AcademicYearPicker('));
      expect(screen, contains("key: const Key('zcYearPicker')"));
      // ⚠ 选择器的年份 = 学年**开始**年，综测内部一律用**结束**年 → 必须 +1 换算
      //   （2026-09-27 之前直接传 `_year`，高亮对右半边落在 endYear 之外）。
      expect(screen, contains('onChanged: (y) => _loadYear(y + 1)'));
      expect(screen, contains('zcYearPickerRange('));
      expect(screen.contains("tooltip: '上一学年'"), isFalse);
      expect(screen.contains("tooltip: '下一学年'"), isFalse);
      expect(screen.contains('_switchYear'), isFalse, reason: '旧方法应已删除');
    });

    test('★ 学年选择器的范围与年份语义（用户 2026-09-27：「只显示到了 2026，应该显示到 2027」）', () {
      // 2026-09：最新测评学年 = 2025-2026（结束年 2026）。
      final r = zcYearPickerRange(latestEnd: 2026, yearEnd: 2026);
      expect(r.initialYear, 2025, reason: '选择器年份 = 学年开始年（2025-2026 → 2025）');
      expect(r.endYear, 2027, reason: 'endYear 要多留一格，配对才有右半边「2027」');
      expect(r.startYear, 2021, reason: '往前 5 个学年（2021-2022 是最老的一档）');
      // 高亮对 = initialYear ~ initialYear+1 = 2025-2026 ✓，且右半边 ≤ endYear-1
      expect(r.initialYear + 1 <= r.endYear - 1, isTrue);
      // 当前学年（2026-2027）也够得着：initialYear 能一直选到 endYear-1
      expect(r.endYear - 1, 2026, reason: '2026-2027 学年 = 开始年 2026');

      // 切到当前学年后（_year = 2027）仍然夹得住
      final r2 = zcYearPickerRange(latestEnd: 2026, yearEnd: 2027);
      expect(r2.initialYear, 2026);
      expect(r2.initialYear <= r2.endYear - 1, isTrue);
      // 越界的 _year 会被夹回范围（不留一个选不中的值）
      final r3 = zcYearPickerRange(latestEnd: 2026, yearEnd: 2099);
      expect(r3.initialYear, 2026);
      final r4 = zcYearPickerRange(latestEnd: 2026, yearEnd: 1900);
      expect(r4.initialYear, r4.startYear);
    });

    test('★ 选择器右侧有「学年」二字（用户 2026-09-27：「就像成绩页一样」）', () {
      final code = screen
          .split('\n')
          .map((line) => line.split('//').first)
          .join('\n');
      final at = code.indexOf('Widget _buildYearBar(BuildContext context) {');
      final block = code.substring(at, code.indexOf('\n  }', at));
      expect(block, contains("'学年'"), reason: '标签必须在选择器同一行里');
      expect(block, contains('mainAxisSize: MainAxisSize.min'));
    });

    testWidgets('★ 新范围要真的画得出「2027」（旧参数下这一项压根不存在）', (tester) async {
      final r = zcYearPickerRange(latestEnd: 2026, yearEnd: 2026);
      Widget host(int startYear, int endYear, int initialYear) => MaterialApp(
        home: Scaffold(
          body: AcademicYearPicker(
            startYear: startYear,
            endYear: endYear,
            initialYear: initialYear,
          ),
        ),
      );

      await tester.pumpWidget(host(r.startYear, r.endYear, r.initialYear));
      await tester.pumpAndSettle();
      // 高亮对 = 2025 + 「-」 + 2026，且 2027 作为条目存在（能一直选到 2026-2027）
      expect(find.text('2025'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      expect(
        find.text('2027'),
        findsOneWidget,
        reason: '右半边要有实体，否则标签只剩「2026 -」——用户看到的正是这个',
      );

      // 旧口径（endYear = 最新学年那年）：列表到不了 2027 → 复现用户报的现象
      await tester.pumpWidget(host(2021, 2026, 2026));
      await tester.pumpAndSettle();
      expect(find.text('2027'), findsNothing);
    });

    test('顶部只剩一个**居中**的学年选择器，左侧提示文本已撤（用户 2026-09-27 四轮）', () {
      // 只扫代码（注释里会引用被删掉的旧写法做说明，不能当违规）。
      final code = screen
          .split('\n')
          .map((line) => line.split('//').first)
          .join('\n');
      final at = code.indexOf('Widget _buildYearBar(BuildContext context) {');
      expect(at, greaterThan(0), reason: '_buildYearBar 应还在');
      final block = code.substring(at, code.indexOf('\n  }', at));
      expect(block, contains('Center('), reason: '选择器必须居中');
      expect(block, contains("key: const Key('zcYearPicker')"));
      for (final gone in const ['测评学年', '9 月起测评上一学年', 'onHoverChanged']) {
        expect(block.contains(gone), isFalse, reason: '「$gone」应已从顶部撤掉');
      }
      expect(
        code.contains('_pickerHovered'),
        isFalse,
        reason: '悬停淡出（只服务于左侧那两行）连字段一起删掉，留着会报 unused_field',
      );
    });

    test('志愿服务时长 = 单行胶囊 + 下方按表 18 分段的进度条（无说明文案）', () {
      // 标题不再带「（按表 18 档位换算）」（用户 2026-09-18 二轮：「提示文本太多
      // ……都要去掉」）；条也不收 accent / loading（颜色固定主题红、没有文案行）。
      expect(screen, contains("'志愿服务时长'"));
      // 只扫代码（`//` 之后的注释里可以提到它，用户要求撤掉的是**界面文案**）。
      final code = screen
          .split('\n')
          .map((line) => line.split('//').first)
          .join('\n');
      expect(
        code.contains('按表 18'),
        isFalse,
        reason: '行标题里的档位说明已撤掉',
      );
      expect(screen, contains('ZcVolunteerBar(hours: r.volunteerUsed)'));
      expect(
        screen.contains('scoreText:'),
        isFalse,
        reason: '旧的 zcEditRow + scoreText 两段式已并入单行胶囊',
      );
    });

    test('次数型条目：步进器挂在行右侧（trailing）且是胶囊', () {
      // 用户 2026-09-18：「我希望把所有次数型的项，其次数修改组件放到条目右侧，
      // 并改成胶囊」→ 9 处次数项从两段式 `_editRow(child: CountStepper(…))`
      // 改成单行 `_subRow(…, trailing: CountStepper(…))`（圆点标记 + 右侧胶囊）。
      final trailing = RegExp(r'trailing: CountStepper\(').allMatches(screen).length;
      expect(trailing, 9, reason: '缺课/缺席/实训/扰乱×2/退团/弃权×2/劳育 = 9 处');
      expect(
        RegExp(r'child: CountStepper\(').hasMatch(screen),
        isFalse,
        reason: '不能再挂在行中间',
      );
    });

    test('外语行标题取原文条目名（认不出才回落证书名）', () {
      expect(screen, contains('zcForeignEntryLabel('));
      expect(screen, contains('m.typeId == ZcTypeId.foreign'));
      expect(screen, contains('m.displayName'), reason: '兜底仍是证书名');
    });

    test('智育竞赛条目多一行备注（用户 2026-09-18：「智育的竞赛条目上也要显示竞赛的备注信息」）', () {
      expect(
        screen,
        contains('m.typeId == ZcTypeId.contest && m.note.trim().isNotEmpty'),
      );
      expect(screen, contains('m.note.trim()'), reason: '备注文本按原样渲染');
    });
  });

  group('结果卡改版（用户 2026-09-21）', () {
    // 用户原话：「我希望综测顶部汇总卡片不要显示：占比 20 / 35 / 15 / 15 / 15、
    // 加权成绩 91.86 分、材料条数 13 条 这些信息，而是把占比显示到每个“育”的
    // 名称后面」+「“测评结果”改成“总评成绩”，右侧显示总评成绩」+「去除
    // “填写/录入后自动计算，实时更新”」。
    late List<ZcWeights> edited;

    setUp(() => edited = <ZcWeights>[]);

    Future<void> pumpResult(WidgetTester tester, ZcCalcResult result) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => SingleChildScrollView(
                child: zcResultCard(context, result, onEditWeights: edited.add),
              ),
            ),
          ),
        ),
      );
    }

    Future<ZcCalcResult> pumpCard(
      WidgetTester tester,
      ZcWeights weights,
    ) async {
      final result = zcCalculate(
        const <ZcMaterial>[],
        manual: ZcManual(weights: weights),
      );
      await pumpResult(tester, result);
      return result;
    }

    testWidgets('头部 = 「总评成绩」+ 右侧纯文字大号总分（无胶囊 / 无铅笔），副标题已撤', (
      tester,
    ) async {
      final r = await pumpCard(tester, ZcWeights.initial);
      expect(find.text('总评成绩'), findsOneWidget);
      expect(find.text('测评结果'), findsNothing, reason: '标题已改名');
      expect(
        find.text('填写/录入后自动计算，实时更新'),
        findsNothing,
        reason: '副标题整条删掉',
      );
      final chip = find.byKey(const Key('zcTotalChip'));
      expect(chip, findsOneWidget);
      expect(find.text('${zcFmt2(r.total)} 分'), findsOneWidget);
      expect(find.text('综合等次'), findsOneWidget, reason: '等次胶囊保留在右侧');
      // 用户 2026-09-21 二轮：「总评成绩不要显示为胶囊」+「分数可点，但是不显示
      // 铅笔图标」（原话）。
      expect(
        find.descendant(of: chip, matching: find.byIcon(Icons.edit_outlined)),
        findsNothing,
        reason: '不再有铅笔提示（分数仍可点）',
      );
      expect(
        [
          for (final c in tester.widgetList<Container>(
            find.descendant(of: chip, matching: find.byType(Container)),
          ))
            c.decoration,
        ].whereType<Decoration>(),
        isEmpty,
        reason: '不再有胶囊底色 / 描边（纯文字）',
      );
      expect(
        tester.widget<Text>(find.text('${zcFmt2(r.total)} 分')).style!.color,
        _gradeColor(r.overall),
        reason: '总分按综合等次上色（用户拍板「也按综合等次上色」）',
      );
    });

    testWidgets('育名与占比胶囊 = 默认（中性）色，分数与等次胶囊取等次色（用户 2026-09-27 四轮）', (
      tester,
    ) async {
      // 用户原话：「应该是“x育”与占比显示为此育的颜色，只有分数按等次显示」。
      const r = ZcCalcResult(
        deyu: 60,
        zhiyu: 102.86,
        tiyu: 67.8,
        meiyu: 80,
        laoyu: 84,
        gD: ZcGrade.pass,
        gZ: ZcGrade.ok,
        gT: ZcGrade.good,
        gM: ZcGrade.ok,
        gL: ZcGrade.ok,
        overall: ZcGrade.ok,
        details: <ZcDetail>[],
        weightUsed: 91.86,
        weightAuto: true,
        volunteerUsed: 24,
        volunteerAuto: true,
        weightMissing: false,
        total: 82.77,
        weights: ZcWeights.initial,
      );
      await pumpResult(tester, r);

      // ① 育名 = 默认文字色（不再取该育语义色 —— 用户 2026-09-27 四轮）
      for (final name in const ['德育', '智育', '体育', '美育', '劳育']) {
        expect(
          tester.widget<Text>(find.text(name)).style!.color,
          isNull,
          reason: '「$name」用默认颜色，不带 color',
        );
      }

      // ② 占比胶囊 = 中性灰（同色文字 + 同色淡底；default 占比下 20% / 35% 各一枚）
      final ctx = tester.element(find.text('20%'));
      final outline = Theme.of(ctx).colorScheme.outline;
      for (final key in const ['20%', '35%']) {
        expect(
          tester.widget<Text>(find.text(key)).style!.color,
          outline,
          reason: '$key 文字用中性灰（不再取该育色）',
        );
        final box = tester.widget<Container>(
          find
              .ancestor(of: find.text(key), matching: find.byType(Container))
              .first,
        );
        expect(
          (box.decoration! as BoxDecoration).color,
          AppColors.tint(ctx, outline, 0.12),
          reason: '$key 底色 = 中性灰 12% 淡底',
        );
      }

      // ③ 分数 = 等次色（与育色无关）
      const scores = <String, ZcGrade>{
        '60 分': ZcGrade.pass,
        '102.86 分': ZcGrade.ok,
        '67.8 分': ZcGrade.good,
        '80 分': ZcGrade.ok,
        '84 分': ZcGrade.ok,
      };
      for (final e in scores.entries) {
        expect(
          tester.widget<Text>(find.text(e.key)).style!.color,
          _gradeColor(e.value),
          reason: '「${e.key}」取${e.value.label}的颜色',
        );
      }

      // ④ 行尾等次小胶囊仍是等次色（「优秀」出现 4 次，只取唯一的两个）
      for (final e in const {'合格': ZcGrade.pass, '良好': ZcGrade.good}.entries) {
        expect(
          tester.widget<Text>(find.text(e.key)).style!.color,
          _gradeColor(e.value),
          reason: '等次胶囊「${e.key}」取等次色',
        );
      }
    });

    testWidgets('占比挪到每育名称后：五枚胶囊各取自己那一育的占比', (tester) async {
      await pumpCard(tester, const ZcWeights(d: 11, z: 22, t: 33, m: 44, l: 55));
      const labels = ['11%', '22%', '33%', '44%', '55%'];
      for (final label in labels) {
        expect(find.text(label), findsOneWidget, reason: '$label 应恰好一枚');
      }
      final ys = [for (final label in labels) tester.getTopLeft(find.text(label)).dy];
      expect(
        ys,
        orderedEquals([...ys]..sort()),
        reason: '竖序必须是 德育 → 智育 → 体育 → 美育 → 劳育',
      );
    });

    testWidgets('加权成绩 / 材料条数 / 「占比 …」那行都不再出现', (tester) async {
      await pumpCard(tester, ZcWeights.initial);
      expect(find.text('加权成绩'), findsNothing);
      expect(find.text('材料条数'), findsNothing);
      expect(find.byKey(const Key('zcTotalWeightsLabel')), findsNothing);
      expect(find.textContaining('占比'), findsNothing);
    });

    testWidgets('点头部大号总分 = 改占比入口（弹层口径不变）', (tester) async {
      await pumpCard(tester, ZcWeights.even);
      await tester.tap(find.byKey(const Key('zcTotalChip')));
      await tester.pump();
      expect(edited, [ZcWeights.even]);
    });
  });
}

/// 综测页源码（2026-09-20 架构审查 ⑥：渲染工具箱已外提到 `zongce_widgets.dart`）。
///
/// 守卫改读**两文件并集** —— 原意不变（这些形态必须存在于综测页这一族里），
/// 只是不再假设它们住在同一个文件里。
String _zcSrc() => [
  // ⚠ 2026-10-08：综测页要按类拆分 + 五育卡去重，故守卫改为扫**整族目录**，
  // 不再假设这些形态住在哪两个具体文件里（原意不变：形态必须存在于这一族）。
  ...Directory('lib/features/zongce/presentation')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path),
].map((p) => File(p).readAsStringSync()).join('\n');

/// 等次色的测试侧对照表（与 `zcGradeColor` 同值；色值唯一出处 =
/// `lib/design/status_palette.dart` 的 `ZongceTone`）。
Color _gradeColor(ZcGrade g) => switch (g) {
  ZcGrade.ok => ZongceTone.gradeOk,
  ZcGrade.good => ZongceTone.gradeGood,
  ZcGrade.pass => ZongceTone.gradePass,
  ZcGrade.fail => ZongceTone.gradeFail,
};