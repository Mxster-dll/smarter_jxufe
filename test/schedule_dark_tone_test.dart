import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_tone.dart';

/// 用户 2026-09-17 报：「课表的颜色没有做深色适配」。
///
/// 课表原来有两份**硬编码的浅色 pastel 色表**（竖版 / 横版各一份），深色主题下
/// 仍是浅底 + 深字。修复 = 色表收到 `schedule_tone.dart` 一处，浅色逐值冻结、
/// 深色换「同色相实底 + 柔光灰文字」。用户同日四轮口径：「文字用白色」→
/// 「不要用纯白，太亮」→「课程名还是太亮」（落到 `#C8C8C8`）→
/// 「课程卡片颜色较暗，稍微提亮一点」（底色 `darkFillAlpha` 0.20 → 0.28）。
/// 下面四组守卫：
/// 1. 浅色零漂移（逐值等于原 pastel，含文字色）；
/// 2. 深色确实换了色（底不透明且不等于原色 / 文字是柔和白且压得住底 /
///    表头是**实心深红**而不是提亮红）；
/// 3. 两个课表视图**真的**用上了它（渲染出来的格子底色 = `ScheduleTone.fill`），
///    且源码里不许再有第二份色表。
/// 4. 「停课 / 已调走」的灰色降级态不被浅字覆盖。
///
/// WCAG 相对亮度对比度（与 `lib/design/app_theme.dart` 的私有实现同式）。
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

/// CIELAB ΔE76（sRGB → XYZ(D65) → Lab）—— 「两个色看起来像不像」的客观尺子。
/// 对比度只比亮度：两个亮度相同、色相不同的色，对比度是 1.0 却一眼能分。
double _deltaE(Color a, Color b) {
  List<double> lab(Color c) {
    double lin(double v) =>
        v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    final r = lin(c.r), g = lin(c.g), bl = lin(c.b);
    final x = (r * 0.4124 + g * 0.3576 + bl * 0.1805) / 0.95047;
    final y = r * 0.2126 + g * 0.7152 + bl * 0.0722;
    final z = (r * 0.0193 + g * 0.1192 + bl * 0.9505) / 1.08883;
    double f(double t) => t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
    final fx = f(x), fy = f(y), fz = f(z);
    return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
  }

  final la = lab(a), lb = lab(b);
  return math.sqrt(
    math.pow(la[0] - lb[0], 2) + math.pow(la[1] - lb[1], 2) + math.pow(la[2] - lb[2], 2),
  ).toDouble();
}

void main() {
  ScheduleEntry entry({
    String courseCode = 'C1',
    String courseName = '高等数学',
    String classroom = '麦三教101',
    DayOfWeek day = DayOfWeek.monday,
    int startPeriod = 1,
    int endPeriod = 2,
  }) => ScheduleEntry(
    classCode: '$courseCode-01',
    className: '$courseName(01)',
    courseCode: courseCode,
    courseName: courseName,
    totalHours: 48,
    credits: 3,
    studyNature: '必修',
    teacherCode: 'T1',
    teacherName: '张三',
    selectionStatus: '已选',
    isCrossMajor: false,
    hasTextbook: true,
    classTimes: [
      ClassTime(
        startWeek: 1,
        endWeek: 16,
        weekParity: WeekParity.every,
        dayOfWeek: day,
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        classroom: classroom,
      ),
    ],
  );

  /// 在给定主题下取一次 context 并跑 [body]。
  Future<T> withTheme<T>(
    WidgetTester tester, {
    required bool dark,
    required T Function(BuildContext context) body,
  }) async {
    late T result;
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? appDarkTheme : appLightTheme,
        home: Builder(
          builder: (context) {
            result = body(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return result;
  }

  Future<void> pumpGrid(WidgetTester tester, {required bool dark}) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? appDarkTheme : appLightTheme,
        home: Scaffold(
          body: ScheduleGridView(
            entries: [entry()],
            week: 2,
            weekMonday: DateTime(2026, 9, 7),
            showToggle: false,
          ),
        ),
      ),
    );
  }

  Color? decorationColorOf(WidgetTester tester, Finder finder) {
    final container = tester.widget<Container>(
      find.ancestor(of: finder, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration;
    return decoration is BoxDecoration ? decoration.color : container.color;
  }

  group('ScheduleTone：浅色逐值冻结（浅色侧一个色值都不许动）', () {
    testWidgets('底板 / 文字逐值等于原 pastel 色表', (tester) async {
      final result = await withTheme<List<String>>(
        tester,
        dark: false,
        body: (context) => [
          for (var i = 0; i < ScheduleTone.courseFills.length; i++)
            '${ScheduleTone.fill(context, i).toARGB32()}'
            '/${ScheduleTone.name(context, i).toARGB32()}'
            '/${ScheduleTone.meta(context, i).toARGB32()}',
        ],
      );
      expect(result, [
        for (var i = 0; i < ScheduleTone.courseFills.length; i++)
          '${ScheduleTone.courseFills[i].toARGB32()}'
          '/${ScheduleTone.courseTexts[i].toARGB32()}'
          '/${ScheduleTone.courseTexts[i].toARGB32()}',
      ]);
      // 取模：负数下标也要落回合法色（`hashCode.abs()` 之外还有人传 -1）。
      expect(
        await withTheme<int>(
          tester,
          dark: false,
          body: (context) =>
              ScheduleTone.fill(context, -1).toARGB32(),
        ),
        ScheduleTone.courseFills.last.toARGB32(),
      );
    });

    testWidgets('补课格底板与表头红浅色原样', (tester) async {
      final band = await withTheme<List<int>>(
        tester,
        dark: false,
        body: (context) => [
          ScheduleTone.tintFill(
            context,
            ScheduleTone.extraFill,
            FeaturePalette.makeUpClass,
          ).toARGB32(),
          ScheduleTone.header(context, ScheduleTone.headerRed).toARGB32(),
        ],
      );
      expect(band, [
        ScheduleTone.extraFill.toARGB32(),
        ScheduleTone.headerRed.toARGB32(),
      ]);
    });
  });

  group('ScheduleTone：深色按色相自适应', () {
    testWidgets('底板换成不透明的同色相实底，且不再等于浅色 pastel', (tester) async {
      final dark = await withTheme<List<Color>>(
        tester,
        dark: true,
        body: (context) => [
          for (var i = 0; i < ScheduleTone.courseFills.length; i++)
            ScheduleTone.fill(context, i),
        ],
      );
      for (var i = 0; i < dark.length; i++) {
        expect(
          dark[i].toARGB32(),
          isNot(ScheduleTone.courseFills[i].toARGB32()),
          reason: '第 $i 色在深色下仍是浅色 pastel',
        );
        expect(dark[i].a, 1.0, reason: '第 $i 色不是实色（半透明会随下层变化）');
        // 深色底必须比浅色 pastel 暗（它是深底上的低透明度同色相叠加）。
        expect(
          dark[i].computeLuminance(),
          lessThan(ScheduleTone.courseFills[i].computeLuminance()),
          reason: '第 $i 色在深色下不够暗',
        );
      }
    });

    testWidgets('课格底不许太暗：第四轮「稍微提亮一点」的取值与不变式', (tester) async {
      // 用户 2026-09-17 第四轮原话：「课表深色模式下，课程卡片颜色较暗，稍微提亮一点」。
      // 初版 0.20 叠出来最亮才 `#234346`（相对亮度 0.048）、与卡片底 `#1A1A1A`
      // 只差 1.26:1，12 色整片发闷。取值点是 [ScheduleTone.darkFillAlpha]。
      expect(
        ScheduleTone.darkFillAlpha,
        0.28,
        reason: '唯一取值点被改动了 —— 要调档请同时更新本测试与文档里的实测表',
      );
      expect(ScheduleTone.darkFillAlpha, greaterThan(0.20), reason: '别再调暗回初版');
      expect(
        ScheduleTone.darkFillAlpha,
        lessThanOrEqualTo(0.30),
        reason: '超过 0.30 课程名 #C8C8C8 就会掉破 4.5:1（0.32 实测 4.49:1）',
      );

      final fills = await withTheme<List<Color>>(
        tester,
        dark: true,
        body: (context) => [
          for (var i = 0; i < ScheduleTone.courseFills.length; i++)
            ScheduleTone.fill(context, i),
        ],
      );
      for (var i = 0; i < fills.length; i++) {
        // 亮度下限：0.20 时最低 0.026、0.28 时最低 0.035 —— 门槛卡在中间。
        expect(
          fills[i].computeLuminance(),
          greaterThanOrEqualTo(0.032),
          reason: '第 $i 个课格底又暗回去了（实测 ${fills[i].computeLuminance()}）',
        );
        // 与卡片底的分离度：0.20 是 1.26:1、0.28 是 1.40:1。
        expect(
          _contrast(fills[i], AppLadder.darkCard),
          greaterThanOrEqualTo(1.35),
          reason: '第 $i 个课格底与卡片底分不开（实测 '
              '${_contrast(fills[i], AppLadder.darkCard).toStringAsFixed(2)}:1）',
        );
      }

      // [ScheduleTone.darkTint] 的默认值必须就是 [ScheduleTone.darkFillAlpha]：
      // 不传 alpha 时与 [ScheduleTone.fill] 逐值相同（补课格走的 tintFill 同源）。
      final tinted = await withTheme<List<Color>>(
        tester,
        dark: true,
        body: (context) => [
          for (var i = 0; i < ScheduleTone.courseTexts.length; i++)
            ScheduleTone.darkTint(context, featureTone(ScheduleTone.courseTexts[i])),
        ],
      );
      for (var i = 0; i < tinted.length; i++) {
        expect(
          tinted[i].toARGB32(),
          fills[i].toARGB32(),
          reason: '第 $i 色：darkTint 的默认档与 fill 不是同一个透明度',
        );
      }
    });

    testWidgets('课程名在深色下用柔光灰 #C8C8C8，且次级行基准色不跟着降（第三轮）', (tester) async {
      // 用户三轮原话：①「我希望深色模式的课表，每个课程内部的文字用白色，
      // 但是浅色模式的显示不变」→ ②「深色模式课程字体颜色不要用纯白，太亮」
      // → ③「感觉课程名的颜色还是太亮」。第 ② 轮只从 `#FFFFFF` 降到 `#EBEBEB`
      // （亮度 −8%，肉眼几乎没差别），所以第 ③ 轮落到真正的一档：课程名
      // [ScheduleTone.darkCourseName] = `#C8C8C8`（比正文色再暗 27% 相对亮度、
      // CIELAB 明度 93.4 → 80.7）。**别再回退纯白或 #EBEBEB。**
      final names = await withTheme<List<Color>>(
        tester,
        dark: true,
        body: (context) => [
          for (var i = 0; i < ScheduleTone.courseTexts.length; i++)
            ScheduleTone.name(context, i),
        ],
      );
      final metas = await withTheme<List<Color>>(
        tester,
        dark: true,
        body: (context) => [
          for (var i = 0; i < ScheduleTone.courseTexts.length; i++)
            ScheduleTone.meta(context, i),
        ],
      );
      for (var i = 0; i < names.length; i++) {
        expect(
          names[i].toARGB32(),
          ScheduleTone.darkCourseName.toARGB32(),
          reason: '第 $i 个课程名色不是柔光灰',
        );
        expect(
          names[i].computeLuminance(),
          lessThan(AppLadder.darkOnSurface.computeLuminance()),
          reason: '第 $i 个课程名没有比全应用正文色更柔（用户嫌太亮）',
        );
        for (final banned in [const Color(0xFFFFFFFF), const Color(0xFFEBEBEB)]) {
          expect(
            names[i].toARGB32(),
            isNot(banned.toARGB32()),
            reason: '第 $i 个课程名退回被用户否掉的亮档了',
          );
        }
        expect(names[i].a, 1.0, reason: '课程名必须是实色（半透明会随底板变化）');
        // 次级行（教师 / 教室 / 周次）的**基准**色不动：它们本来就比课名暗
        // （α140 那档压在暗底上只有 3.91:1），跟着降会掉到 3.2:1。
        expect(
          metas[i].toARGB32(),
          AppLadder.darkOnSurface.toARGB32(),
          reason: '第 $i 个次级行基准色被连带降级了（教师/教室会读不清）',
        );
      }
    });

    testWidgets('课程名压在同色相实底上必须 ≥ 4.5:1（对比度是这次改动的目的）', (tester) async {
      final pairs = await withTheme<List<(Color, Color)>>(
        tester,
        dark: true,
        body: (context) => [
          for (var i = 0; i < ScheduleTone.courseFills.length; i++)
            (ScheduleTone.name(context, i), ScheduleTone.fill(context, i)),
        ],
      );
      for (var i = 0; i < pairs.length; i++) {
        final (name, fill) = pairs[i];
        expect(
          _contrast(name, fill),
          greaterThanOrEqualTo(4.5),
          reason: '第 $i 色的课程名压在该色实底上不足 4.5:1（实测 '
              '${_contrast(name, fill).toStringAsFixed(2)}）',
        );
      }
    });

    testWidgets('表头是**实心深红**（不是提亮红）：白字够 AA，且不被翻成近黑字', (tester) async {
      // 用户 2026-09-17 第二轮：「顶部周几的文本不要用深灰，太暗」。
      // 成因：表头原先走 `ScheduleTone.header`（= featureTone 提亮成 `#D96363`），
      // 白字只有 3.55:1 → `AppColors.onAccent` 择了近黑字 `#1A1A1A`。
      // 修法：表头是**实心件**，按 §22 用深饱和档 [ScheduleTone.headerFill]。
      final band = await withTheme<List<Color>>(
        tester,
        dark: true,
        body: (context) => [
          ScheduleTone.tintFill(
            context,
            ScheduleTone.extraFill,
            FeaturePalette.makeUpClass,
          ),
          ScheduleTone.headerFill(context, ScheduleTone.headerRed),
          ScheduleTone.headerFill(context, ScheduleTone.weekendHeader),
          // 切换图标仍走「提亮」那条路（它是线稿，不是实心底）。
          ScheduleTone.header(context, ScheduleTone.headerRed),
        ],
      );
      expect(band[0].toARGB32(), isNot(ScheduleTone.extraFill.toARGB32()));
      expect(
        band[1].toARGB32(),
        ScheduleTone.headerRed.toARGB32(),
        reason: '深色下表头红被提亮了（实心件不许提亮：白字会掉到 3.55:1）',
      );
      expect(
        band[2].toARGB32(),
        ScheduleTone.weekendHeader.toARGB32(),
        reason: '周末表头底也该保持原深蓝灰',
      );
      // 图标那条路仍要提亮（压在页面底上的线稿必须够亮）。
      expect(
        band[3].toARGB32(),
        isNot(ScheduleTone.headerRed.toARGB32()),
        reason: '切换图标的提亮没了（线稿压在深色页面底上会看不清）',
      );
      expect(
        band[3].computeLuminance(),
        greaterThan(ScheduleTone.headerRed.computeLuminance()),
      );
      // 关键：两档表头底压白字都必须 ≥ 4.5:1（这样 onAccent 才会择白）。
      for (final fill in [band[1], band[2]]) {
        final white = _contrast(const Color(0xFFFFFFFF), fill);
        final ink = _contrast(AppLadder.darkOnPrimary, fill);
        expect(white, greaterThanOrEqualTo(4.5), reason: '白字压表头底只有 $white');
        expect(white, greaterThan(ink), reason: '白字不是更优解 → onAccent 会翻成深灰字');
      }
    });
  });

  group('课表视图真的用上了 ScheduleTone', () {
    testWidgets('深色：课程格底色 = ScheduleTone.fill，表头 = 深红底 + 白字', (tester) async {
      await pumpGrid(tester, dark: true);
      final context = tester.element(find.byType(ScheduleGridView));
      // 色号 = **按课程身份发的号**（用户 2026-09-17：「优先保证每门课程的颜色都
      // 不同」）：本用例只有一门课 → 下标 0，不再走 `courseCode.hashCode`。
      expect(
        decorationColorOf(tester, find.text('高等数学'))?.toARGB32(),
        ScheduleTone.fill(context, 0).toARGB32(),
      );
      // 表头是实心件：深浅两档都是原深红 / 原深蓝灰（不提亮）。
      expect(
        decorationColorOf(tester, find.text('周一'))?.toARGB32(),
        ScheduleTone.headerRed.toARGB32(),
        reason: '深色表头底被提亮了 → 白字会掉到 3.55:1 并被翻成深灰字',
      );
      expect(
        decorationColorOf(tester, find.text('周六'))?.toARGB32(),
        ScheduleTone.weekendHeader.toARGB32(),
      );
      // 表头文字必须按对比度择色 —— 深色下这两档都该择**白**（用户
      // 2026-09-17：「顶部周几的文本不要用深灰，太暗」）。
      final headerFg = AppColors.onAccent(context, ScheduleTone.headerRed);
      expect(
        headerFg.toARGB32(),
        const Color(0xFFFFFFFF).toARGB32(),
        reason: '深色表头文字不是白字（会变成用户抱怨的深灰）',
      );
      expect(
        tester.widget<Text>(find.text('周一')).style?.color?.toARGB32(),
        headerFg.toARGB32(),
      );
    });

    testWidgets('浅色：课程格仍是原 pastel（渲染层零漂移）', (tester) async {
      await pumpGrid(tester, dark: false);
      // 同上：唯一一门课的身份号 = 0（不再是 `hashCode`）。
      expect(
        decorationColorOf(tester, find.text('高等数学'))?.toARGB32(),
        ScheduleTone.courseFills[0].toARGB32(),
      );
      expect(
        decorationColorOf(tester, find.text('周一'))?.toARGB32(),
        ScheduleTone.headerRed.toARGB32(),
      );
      expect(
        tester.widget<Text>(find.text('周一')).style?.color?.toARGB32(),
        const Color(0xFFFFFFFF).toARGB32(),
        reason: '浅色下表头必须仍是纯白字（onAccent 浅色恒返回白）',
      );
    });
  });

  group('课程名色（用户 2026-09-17 三轮：白色 → 柔和白 → 柔光灰；浅色不变）', () {
    testWidgets('深色：课程名渲染成柔光灰 #C8C8C8（渲染层）', (tester) async {
      await pumpGrid(tester, dark: true);
      expect(
        tester.widget<Text>(find.text('高等数学')).style?.color?.toARGB32(),
        ScheduleTone.darkCourseName.toARGB32(),
        reason: '深色下课程名不是柔光灰（纯白 / #EBEBEB 都被用户否掉：太亮）',
      );
    });

    testWidgets('浅色：课程名仍是原深色文字（渲染层零漂移）', (tester) async {
      await pumpGrid(tester, dark: false);
      expect(
        tester.widget<Text>(find.text('高等数学')).style?.color?.toARGB32(),
        ScheduleTone.courseTexts[0].toARGB32(),
        reason: '浅色侧一个色值都不许动',
      );
    });

    test('课程名与次级行是两个 token（源码守卫）', () {
      // 课名走 `nameColor`（深色下更柔）、次级行走 `textColor.withAlpha(...)`
      // （基准色不动）—— 合并任意一侧都会让用户已经否掉的问题回来。
      for (final path in [
        'lib/features/ims/schedule/presentation/schedule_grid_view.dart',
        'lib/features/ims/schedule/presentation/schedule_horizontal_view.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('ScheduleTone.name(context, colorSeed)'),
          isTrue,
          reason: '$path 的课名没走 ScheduleTone.name',
        );
        expect(
          src.contains('ScheduleTone.meta(context, colorSeed)'),
          isTrue,
          reason: '$path 的次级行没走 ScheduleTone.meta',
        );
        expect(
          src.contains('textColor.withAlpha('),
          isTrue,
          reason: '$path 的次级行不再按 α 淡化（会与课名同亮）',
        );
      }
      // 课名那行必须用 nameColor，不许回退成 textColor。
      final grid = File(
        'lib/features/ims/schedule/presentation/schedule_grid_view.dart',
      ).readAsStringSync();
      expect(grid.contains('color: nameColor,'), isTrue);
    });

    test('「停课 / 已调走」的灰色降级态不被白字覆盖（源码守卫）', () {
      // 白字只用于**正常课程格**：调走 / 停课格是刻意灰掉的语义降级态
      // （`AppColors.textMuted` + 删除线），改成白字会毁掉那个信号。
      // 这两种状态要构造完整的 `Reschedule` 才能渲染出来，这里直接守源码：
      // 两个视图的 switch 里必须仍有把 textColor 覆盖成 textMuted 的两个分支。
      for (final path in [
        'lib/features/ims/schedule/presentation/schedule_grid_view.dart',
        'lib/features/ims/schedule/presentation/schedule_horizontal_view.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('case EffectiveMark.movedAway:'),
          isTrue,
          reason: '$path 少了「已调走」分支',
        );
        expect(
          src.contains('textColor = AppColors.textMuted(context);'),
          isTrue,
          reason: '$path 的降级态没有覆盖成 textMuted（会被白字毁掉）',
        );
      }
    });
  });

  group('课程配色扩表（用户 2026-09-17 五轮：颜色不够丰富，加一两种）', () {
    test('两张色表等长共 14 色，末尾 2 色是新增的玫红 / 青绿', () {
      expect(ScheduleTone.courseFills.length, 14);
      expect(ScheduleTone.courseTexts.length, ScheduleTone.courseFills.length);
      // 前 12 色是原 `_coursePalette` / `_textPalette`，一个值都不许动（浅色冻结）。
      expect(ScheduleTone.courseFills.take(12).toSet().length, 12);
      expect(ScheduleTone.courseFills[12].toARGB32(), 0xFFF8BBD0, reason: '玫红底板');
      expect(ScheduleTone.courseTexts[12].toARGB32(), 0xFF880E4F, reason: '玫红文字');
      expect(ScheduleTone.courseFills[13].toARGB32(), 0xFFE0F2F1, reason: '青绿底板');
      expect(ScheduleTone.courseTexts[13].toARGB32(), 0xFF00695C, reason: '青绿文字');
    });

    testWidgets('新增色必须真的「新」：与既有 12 色的深色底 ΔE76 ≥ 6', (tester) async {
      // 反例就在原表里：浅粉 ↔ 浅红的深色底 ΔE 只有 **1.6**（肉眼同色）——
      // 扩表的意义正是别再往里塞「看着一样」的颜色，所以这条卡在 6。
      // 实测新增色：玫红 13.2（最像浅粉）、青绿 6.9（最像浅青）。
      final fills = await withTheme<List<Color>>(
        tester,
        dark: true,
        body: (context) => [
          for (var i = 0; i < ScheduleTone.courseFills.length; i++)
            ScheduleTone.fill(context, i),
        ],
      );
      for (final i in [12, 13]) {
        var min = double.infinity;
        var who = -1;
        for (var j = 0; j < 12; j++) {
          final d = _deltaE(fills[i], fills[j]);
          if (d < min) {
            min = d;
            who = j;
          }
        }
        expect(
          min,
          greaterThanOrEqualTo(6.0),
          reason: '第 $i 色与第 $who 色的深色底 ΔE 只有 ${min.toStringAsFixed(1)}（<6 基本分不出来）',
        );
      }
    });

    testWidgets('新增色的浅色档也不是既有色的复制（浅底 ΔE ≥ 2.5、文字压底 ≥ 4.0）', (tester) async {
      // 浅色 pastel 全是同一档次亮度（HSL 92~97%），彼此 ΔE 本来就小
      // （原表里 浅绿 ↔ 浅黄绿 = 2.9），所以这里的门槛只用来挡「直接复制一个色」。
      for (final i in [12, 13]) {
        var min = double.infinity;
        for (var j = 0; j < 12; j++) {
          min = math.min(min, _deltaE(ScheduleTone.courseFills[i], ScheduleTone.courseFills[j]));
        }
        expect(
          min,
          greaterThanOrEqualTo(2.5),
          reason: '第 $i 色的浅色底板与既有色几乎一样（ΔE ${min.toStringAsFixed(1)}）',
        );
        expect(
          _contrast(ScheduleTone.courseTexts[i], ScheduleTone.courseFills[i]),
          greaterThanOrEqualTo(4.0),
          reason: '第 $i 色浅色下课程名压不住底板',
        );
      }
    });

    testWidgets('新增色的取模落点合法（14 色都能取到，负数也安全）', (tester) async {
      final got = await withTheme<List<int>>(
        tester,
        dark: false,
        body: (context) => [
          for (var seed = 0; seed < 14; seed++) ScheduleTone.fill(context, seed).toARGB32(),
        ],
      );
      expect(got.toSet().length, 14, reason: '14 个 seed 应该拿到 14 个不同底板');
      expect(
        await withTheme<int>(
          tester,
          dark: false,
          body: (context) => ScheduleTone.fill(context, -1).toARGB32(),
        ),
        ScheduleTone.courseFills.last.toARGB32(),
        reason: '-1 应落回最后一色（扩表后是青绿）',
      );
    });
  });

  group('源码守卫：课程色表只有一份', () {
    final views = [
      'lib/features/ims/schedule/presentation/schedule_grid_view.dart',
      'lib/features/ims/schedule/presentation/schedule_horizontal_view.dart',
    ];

    test('两个视图里不许再有硬编码课程色表', () {
      for (final path in views) {
        final src = File(path).readAsStringSync();
        expect(src.contains('_coursePalette'), isFalse, reason: '$path 还留着旧色表');
        expect(src.contains('_textPalette'), isFalse, reason: '$path 还留着旧色表');
        expect(
          src.contains('0xFFE3F2FD'),
          isFalse,
          reason: '$path 又抄了一份 courseFills',
        );
        expect(
          src.contains('schedule_tone.dart'),
          isTrue,
          reason: '$path 没引用 ScheduleTone',
        );
      }
    });

    test('色表唯一定义在 schedule_tone.dart', () {
      final tone = File(
        'lib/features/ims/schedule/presentation/schedule_tone.dart',
      ).readAsStringSync();
      expect(tone.contains('0xFFE3F2FD'), isTrue);
      expect(tone.contains('class ScheduleTone'), isTrue);
    });
  });
}
