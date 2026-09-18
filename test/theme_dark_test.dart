/// 深色模式（2026-09-16）的守卫。
///
/// 用户原话：「给应用适配深色模式」。三个口径由用户逐项拍板：
/// ① 深色底色阶梯 = **A · 中性深灰**（看过 `design_preview/dark_mode_preview.html`
///    的四列对比后回了一个字「A」）；
/// ② 深色强调色 = **亮红档 `#F2555A`**（用户 2026-09-16 上机后反馈「太浅了，
///    回调一些」，由拍板时的 `#FF6B6E` 收深；浅色仍是校徽红 `#C3282E`）；
/// ③ 模式入口 = **设置页「外观」节 · 跟随系统 / 浅色 / 深色 · 默认跟随系统**。
///
/// 本文件守四件事：
/// 1. **浅色逐值不变**（本次改动不许动浅色的任何一个色值）；
/// 2. **深色逐值 = 用户批准的预览取值**（改色值必须先改预览并请用户重看）；
/// 3. **`featureTone` 与预览里的 JS `tone()` 同值**（用 Node 侧同款实现产出的期望值硬编码，
///    见期望表下方注释的算法口径）—— 以及「提亮真的把不可读变成可读」的不变式；
/// 4. **外观偏好的读取 / 落盘 / 设置页入口**，以及 `MaterialApp` 真的跟着切。
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/home/presentation/home_sidebar.dart';
import 'package:smarter_jxufe/features/settings/data/theme_prefs.dart';
import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';

/// 0xAARRGGBB 里取出 RGB 三元组（忽略 alpha，与预览的 `hex2rgb` 同口径）。
(int, int, int) _rgb(Color c) => (
  (c.r * 255).round(),
  (c.g * 255).round(),
  (c.b * 255).round(),
);

/// WCAG 相对亮度（与预览的 `lum()` 同实现）。
double _luminance(Color c) {
  double lin(int v) {
    final s = v / 255;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  final (r, g, b) = _rgb(c);
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

/// WCAG 对比度（与预览的 `contrast()` 同实现）。
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

Future<Directory> _initHive() async {
  final dir = Directory.systemTemp.createTempSync('theme_dark_test');
  Hive.init(dir.path);
  return dir;
}

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await _initHive();
    // ⚠ **必须在这里（真实异步区里）就把 box 打开。**
    // `Hive.openBox` 对同一个 box 名是「单飞」的：第一次打开会挂进内部的
    // `_openingBoxes`。若那一次发生在 `testWidgets` 的假异步区里（例如设置页
    // provider 的 `unawaited(ensureLoaded())`）→ 那个 future 永远不会完成，
    // 之后**任何**一次 `Hive.openBox('themePrefs')` 都会一直等它 →
    // 测试挂到 `pumpAndSettle` 的 10 分钟上限才报 "did not complete"。
    // 预先打开后，假异步区里的 openBox 走「已打开」短路，不再碰真实 I/O。
    await Hive.openBox<String>(themePrefsBoxName);
  });

  tearDownAll(() async {
    // ⚠ `Hive.close()` 会等待所有在途操作，而本文件最后一例在假异步区里留下的那次
    // `box.put` 永远不会完成 → 裸 `await Hive.close()` 会让整份测试挂在收尾
    // （全量跑时表现为 `(tearDownAll) - did not complete`）。这里给它一个上限。
    await Hive.close().timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
    try {
      hiveDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('① 浅色 = 现状逐值不变', () {
    test('底阶 / 强调色', () {
      final s = appLightScheme;
      expect(s.brightness, Brightness.light);
      expect(s.primary, const Color(0xFFC3282E)); // 校徽红
      expect(s.surface, const Color(0xFFFFFFFF));
      expect(s.surfaceContainerLowest, const Color(0xFFFFFFFF));
      expect(s.surfaceContainerLow, const Color(0xFFFAFAFA));
      expect(s.surfaceContainer, const Color(0xFFF5F5F5));
      expect(s.surfaceContainerHigh, const Color(0xFFF0F0F0));
      expect(s.surfaceContainerHighest, const Color(0xFFEBEBEB));
      expect(s.surfaceTint, const Color(0xFFFFFFFF));
      // §3「主题纯白」：白系一律 R=G=B，不从 primary 派生。
      for (final c in [
        s.surface,
        s.surfaceContainerLowest,
        s.surfaceContainerLow,
        s.surfaceContainer,
        s.surfaceContainerHigh,
        s.surfaceContainerHighest,
        s.surfaceTint,
      ]) {
        final (r, g, b) = _rgb(c);
        expect(r, g, reason: '浅色白系必须中性（R=G=B），实际 $c');
        expect(g, b, reason: '浅色白系必须中性（R=G=B），实际 $c');
      }
    });

    test('浅色 ThemeData 的装配也没变（卡片主题 / 字体 / 转场）', () {
      final t = appLightTheme;
      expect(t.colorScheme, appLightScheme);
      expect(t.cardTheme.color, kAppCardColor);
      expect(t.cardTheme.elevation, 0);
      expect(t.cardTheme.surfaceTintColor, const Color(0x00000000));
      expect(t.textTheme.bodyMedium?.fontFamily, 'Cascadia Code');
      // 深色的那几项补丁不许漏到浅色里。
      expect(t.appBarTheme.backgroundColor, isNot(AppLadder.darkTopBar));
      expect(t.dividerColor, isNot(AppLadder.darkDivider));
    });

    testWidgets('浅色下 AppColors 给回原来的裸色取值', (tester) async {
      // 浅色档的角色色 = 改动前那些裸色的等效值（迁移不许改浅色观感）。
      late Color fill;
      late Color fillSoft;
      late Color card;
      late Color stroke;
      late Color textBase;
      late Color textMuted;
      late bool dark;
      late Color success;
      late Color statusFill;

      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: Builder(
            builder: (context) {
              fill = AppColors.fill(context);
              fillSoft = AppColors.fillSoft(context);
              card = AppColors.card(context);
              stroke = AppColors.stroke(context);
              textBase = AppColors.textBase(context);
              textMuted = AppColors.textMuted(context);
              dark = AppColors.isDark(context);
              success = AppColors.success(context);
              statusFill = AppColors.statusFill(context, success);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(dark, isFalse);
      expect(fill, const Color(0xFFF5F5F5)); // = surfaceContainer
      expect(fillSoft, const Color(0xFFFAFAFA)); // = surfaceContainerLow
      expect(card, const Color(0xFFFFFFFF)); // = 原 kAppCardColor
      expect(stroke, appLightScheme.outlineVariant);
      expect(textBase, appLightScheme.onSurface);
      expect(textMuted, appLightScheme.onSurfaceVariant);
      expect(success, FeaturePalette.grade, reason: '浅色下不提亮，原样返回');
      expect(statusFill.a, closeTo(0.12, 1e-9), reason: '浅色状态底 12%');
    });

    testWidgets('深色下 AppColors 走提亮档 + 22% 状态底', (tester) async {
      late Color fill;
      late Color fillSoft;
      late Color fillStrong;
      late Color fillStronger;
      late Color card;
      late Color textBase;
      late Color success;
      late Color statusFill;

      await tester.pumpWidget(
        MaterialApp(
          theme: appDarkTheme,
          home: Builder(
            builder: (context) {
              fill = AppColors.fill(context);
              fillSoft = AppColors.fillSoft(context);
              fillStrong = AppColors.fillStrong(context);
              fillStronger = AppColors.fillStronger(context);
              card = AppColors.card(context);
              textBase = AppColors.textBase(context);
              success = AppColors.success(context);
              statusFill = AppColors.statusFill(context, success);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(fill, const Color(0xFF1E1E1E));
      expect(fillSoft, const Color(0xFF1A1A1A));
      expect(fillStrong, const Color(0xFF242424));
      expect(fillStronger, const Color(0xFF2C2C2C));
      expect(card, const Color(0xFF1A1A1A));
      expect(textBase, const Color(0xFFEBEBEB));
      expect(success, featureTone(FeaturePalette.grade));
      expect(statusFill.a, closeTo(0.22, 1e-9), reason: '深色状态底要更实');
    });
  });

  group('② 深色 = 用户拍板的 A 档', () {
    test('底阶逐值（预览的 --surface/--card/--container/--high/--highest）', () {
      final s = appDarkScheme;
      expect(s.brightness, Brightness.dark);
      expect(s.surface, const Color(0xFF121212));
      expect(s.surfaceContainerLowest, const Color(0xFF121212));
      expect(s.surfaceContainerLow, const Color(0xFF1A1A1A)); // = 卡片色 / 顶栏色
      expect(s.surfaceContainer, const Color(0xFF1E1E1E));
      expect(s.surfaceContainerHigh, const Color(0xFF242424));
      expect(s.surfaceContainerHighest, const Color(0xFF2C2C2C));
      expect(s.surfaceTint, const Color(0xFF121212)); // 中性不着色
      // 深色语义：Lowest 最暗 → Highest 最亮（与浅色相反）。
      final ladder = [
        s.surfaceContainerLowest,
        s.surfaceContainerLow,
        s.surfaceContainer,
        s.surfaceContainerHigh,
        s.surfaceContainerHighest,
      ];
      for (var i = 1; i < ladder.length; i++) {
        expect(
          _luminance(ladder[i]),
          greaterThan(_luminance(ladder[i - 1])),
          reason: '深色底阶必须由暗到亮递增，$ladder 不单调',
        );
      }
      // 中性：R=G=B。
      for (final c in ladder) {
        final (r, g, b) = _rgb(c);
        expect(r, g);
        expect(g, b);
      }
    });

    test('文字 / 描边 / 分隔线逐值（预览的 --text/--text2/--border/--divider）', () {
      final s = appDarkScheme;
      expect(s.onSurface, AppLadder.darkOnSurface);
      expect(s.onSurfaceVariant, AppLadder.darkOnSurfaceVariant);
      expect(s.outlineVariant, AppLadder.darkOutlineVariant);
      expect(s.outline, AppLadder.darkOutline);
      // 主 / 次文字在页面底与卡片底上的对比度都要够小字阅读（≥ 4.5:1）。
      expect(_contrast(s.onSurface, s.surface), greaterThan(4.5));
      expect(_contrast(s.onSurface, s.surfaceContainerLow), greaterThan(4.5));
      expect(_contrast(s.onSurfaceVariant, s.surface), greaterThan(4.5));
      expect(_contrast(s.onSurfaceVariant, s.surfaceContainerLow), greaterThan(4.5));
    });

    test('强调色 = 亮红 #F2555A；浅色仍是校徽红', () {
      expect(appDarkScheme.primary, const Color(0xFFF2555A));
      expect(kBrandRedDark, const Color(0xFFF2555A));
      expect(FeaturePalette.cardAccentDark, const Color(0xFFF2555A));
      expect(appLightScheme.primary, kBrandRed);
      // 亮红上的文字要压深色（浅色压在亮红上只有 2.8:1，读不了）。
      expect(_contrast(appDarkScheme.onPrimary, appDarkScheme.primary), greaterThan(4.5));
      // 亮红当正文/图标色压在页面底上要够亮。
      expect(_contrast(appDarkScheme.primary, appDarkScheme.surface), greaterThan(4.5));
      // 2026-09-16 用户「太浅了，回调一些」：亮红档已由 #FF6B6E 收到 #F2555A。
      // 守住「不许再往亮里调」—— 压页面底的对比度必须低于旧值 6.72:1。
      expect(
        _contrast(appDarkScheme.primary, appDarkScheme.surface),
        lessThan(6.0),
        reason: '亮红档若再提亮就会回到泛粉的观感（用户已否）',
      );
    });

    test('错误红：深色必须是真红，而不是 M3 默认的淡粉 #FFB4AB', () {
      // 成绩页的错误标记 / 虚框 / 进度条吃 `colorScheme.error`；
      // `ColorScheme.fromSeed(brightness: dark)` 给的是 #FFB4AB（几乎发白）。
      expect(appDarkScheme.error, kErrorRedDark);
      expect(kErrorRedDark, const Color(0xFFEE4C50));
      expect(appDarkScheme.error, isNot(const Color(0xFFFFB4AB)));
      // 压在页面底 / 卡片底上都要能当正文色用。
      expect(_contrast(appDarkScheme.error, AppLadder.darkSurface), greaterThan(4.5));
      expect(_contrast(appDarkScheme.error, AppLadder.darkCard), greaterThan(4.5));
      // 压在该错误色上的前景（onError）同样要够。
      expect(_contrast(appDarkScheme.onError, appDarkScheme.error), greaterThan(4.5));
      // 浅色侧不许动（冻结基线）。
      expect(appLightScheme.error, const Color(0xFFBA1A1A));
    });

    test('深色下「红」分两个角色：实心件/描边用深红 #C62828，不许合并回 error', () {
      // 用户 2026-09-16：「我说的是成绩页的按钮背景，卡片的框线，太浅了」。
      // 实心件（chip 底 / 表头）与描边（卡片红框线）不需要跟页面底比对比度，
      // 需要的是「深、饱和、实」；拿当文字用的亮红 #EE4C50 当底会一眼偏浅，
      // 而 error@70% 叠在卡片 #1A1A1A 上混成 #AE3D40 只有 2.93:1（发灰发脏）。
      expect(AppLadder.darkErrorFill, const Color(0xFFC62828));
      expect(AppLadder.darkErrorFill, isNot(appDarkScheme.error));
      // 白字压在深红实心底上要够（5.62:1）。
      expect(AppLadder.darkOnErrorFill, const Color(0xFFFFFFFF));
      expect(
        _contrast(AppLadder.darkOnErrorFill, AppLadder.darkErrorFill),
        greaterThan(4.5),
      );
      // 深红当描边时，与卡片底的图形对比度要够（≥3:1），亮红 @70% 那种混色只有 2.93。
      expect(
        _contrast(AppLadder.darkErrorFill, AppLadder.darkCard),
        greaterThan(3.0),
      );
      expect(
        _contrast(AppLadder.darkErrorFill, AppLadder.darkSurface),
        greaterThan(3.0),
      );
      // 深红**不能**反过来当正文色用（压页面底只有 3.33:1）——两个角色不许互换。
      expect(
        _contrast(AppLadder.darkErrorFill, AppLadder.darkSurface),
        lessThan(4.5),
      );
    });

    test('深色 ThemeData 的补丁：顶栏 = 卡片同色、分隔线用 8% 白', () {
      final t = appDarkTheme;
      expect(t.cardTheme.color, kAppCardColorDark);
      expect(t.appBarTheme.backgroundColor, AppLadder.darkTopBar);
      expect(t.appBarTheme.backgroundColor, kAppCardColorDark);
      expect(t.appBarTheme.surfaceTintColor, const Color(0x00000000));
      expect(t.dividerTheme.color, AppLadder.darkDivider);
      expect(t.textTheme.bodyMedium?.fontFamily, 'Cascadia Code');
    });

    test('卡片描边：浅色 = outlineVariant 60%，深色 = outlineVariant 原值（10% 白）', () {
      expect(
        appCardBorderSide(appLightScheme).color,
        appLightScheme.outlineVariant.withValues(alpha: 0.6),
      );
      expect(appCardBorderSide(appDarkScheme).color, AppLadder.darkOutlineVariant);
      expect(appCardColorOf(appLightScheme), const Color(0xFFFFFFFF));
      expect(appCardColorOf(appDarkScheme), const Color(0xFF1A1A1A));
    });
  });

  group('③ featureTone：与用户过目的预览 JS 逐值同值', () {
    // 期望值 = `design_preview/dark_mode_preview.html` 的
    // `tone(hex, true, 0.62)`（只抬 HSL 明度到 0.62、色相不动、饱和 ×0.92）在 Node 下的输出。
    const expected = <int, int>{
      0xFFC3282E: 0xFFD96368, // 校红 / dashboard
      0xFF2E7D32: 0xFF75C779, // grade / 绿
      0xFF1565C0: 0xFF5799E6, // schedule 蓝
      0xFFEF6C00: 0xFFF79645, // volunteer 橙
      0xFFC62828: 0xFFD96363, // zongce 红
      0xFF5E35B1: 0xFF8E6ECE, // curriculum 紫
      0xFF283593: 0xFF6B77D1, // campusMap
      0xFF3949AB: 0xFF727ECB, // secondClass
      0xFF00838F: 0xFF45E8F7, // graduation / deadlineOnline
      0xFF00897B: 0xFF45F7E5, // campus
      0xFFD81B60: 0xFFE3598B, // dataCenter
      0xFF5C6BC0: 0xFF7782C6, // myMail
      0xFF006064: 0xFF45F0F7, // cxstar
      0xFF00695C: 0xFF45F7E1, // imsSession
      0xFF4527A0: 0xFF8368D4, // publicQuery
      0xFFAD1457: 0xFFE55795, // courseSelection
      0xFF6A1B9A: 0xFFAD60DD, // leave
      0xFF7B1FA2: 0xFFB762DB, // deadlineExam
      0xFFD84315: 0xFFE77755, // reschedule
      0xFFB8860B: 0xFFEDBF4F, // competition
      0xFFF9A825: 0xFFF2B24A, // electricity
      0xFF0277BD: 0xFF47B4F5, // netFee
      0xFF039BE5: 0xFF47BCF5, // calendar
      0xFF00ACC1: 0xFF45E4F7, // liveClass
      0xFF00B8D4: 0xFF45E0F7, // libraryEdu
      0xFF558B2F: 0xFF96CA72, // tice
      0xFF795548: 0xFFB59387, // materials
      0xFF6D4C41: 0xFFB59388, // jhRead
      0xFF546E7A: 0xFF8EA4AF, // studentInfo / calendarEvent
      0xFF455A64: 0xFF8EA4AE, // guidGuide
      0xFF37474F: 0xFF8EA3AE, // rules
      0xFF78909C: 0xFF90A3AC, // deadlineOther
      0xFF757575: 0xFF9E9E9E, // deadlineDone
      0xFF6BB700: 0xFFADF745, // Fluent success
      0xFF9D5D00: 0xFFF7AF45, // Fluent cautionDeep
      0xFFD13438: 0xFFD66669, // Fluent critical
      0xFFFCE100: 0xFFF7E445, // Fluent caution（⚠ 见下：它没有短路）
      // 已经够亮的原样返回（HSL 明度 ≥ 0.62 直接短路）。
      // ⚠ 明度是 **HSL 口径** `(max+min)/2`，不是感知亮度：`#FCE100` 看着很黄很亮，
      // 但 HSL L = (0.988+0)/2 = 0.494 < 0.62 → 照样会被提亮成 `#F7E445`。
      // 口径就是预览里那份 `tone()`，别按「肉眼够亮」去猜哪些会短路。
      0xFF536DFE: 0xFF536DFE, // scoreEstimate
      0xFF90A4AE: 0xFF90A4AE, // scoreEstimateFinal
      0xFFB0BEC5: 0xFFB0BEC5, // scoreEstimatePending
      0xFF9E9E9E: 0xFF9E9E9E, // classCancelled
      0xFF8E8E8E: 0xFF9E9E9E, // Fluent neutral（明度 0.556 < 0.62，会提亮）
    };

    test('逐值一致', () {
      expected.forEach((light, dark) {
        expect(
          featureTone(Color(light)).toARGB32(),
          dark,
          reason:
              'featureTone(${Color(light)}) 必须等于预览里 tone() 的输出 '
              '${Color(dark)}（改口径 = 改用户看过的那份预览，要重新请用户过目）',
        );
      });
    });

    test('色相不动（只抬明度）', () {
      double hue(Color c) {
        final (r, g, b) = _rgb(c);
        final rf = r / 255, gf = g / 255, bf = b / 255;
        final mx = math.max(rf, math.max(gf, bf));
        final mn = math.min(rf, math.min(gf, bf));
        if (mx == mn) return 0;
        final d = mx - mn;
        var h = mx == rf
            ? (gf - bf) / d + (gf < bf ? 6 : 0)
            : mx == gf
            ? (bf - rf) / d + 2
            : (rf - gf) / d + 4;
        return h / 6;
      }

      for (final light in [
        const Color(0xFFC3282E),
        const Color(0xFF1565C0),
        const Color(0xFF2E7D32),
        const Color(0xFFEF6C00),
        const Color(0xFF6A1B9A),
        const Color(0xFF006064),
      ]) {
        final lifted = featureTone(light);
        expect(
          (hue(lifted) - hue(light)).abs(),
          lessThan(0.002),
          reason: '提亮不许动色相：$light → $lifted',
        );
      }
    });

    test('不变式：深色下每个功能色在卡片底上都 ≥ 3:1，且原本不足 4.5:1 的都被抬到更高', () {
      const card = Color(0xFF1A1A1A); // AppLadder.darkCard
      const surface = Color(0xFF121212); // AppLadder.darkSurface
      final palette = {
        'cardAccent': FeaturePalette.cardAccentDark,
        'curriculum': FeaturePalette.curriculum,
        'schedule': FeaturePalette.schedule,
        'grade': FeaturePalette.grade,
        'graduation': FeaturePalette.graduation,
        'studentInfo': FeaturePalette.studentInfo,
        'campus': FeaturePalette.campus,
        'campusMap': FeaturePalette.campusMap,
        'volunteer': FeaturePalette.volunteer,
        'secondClass': FeaturePalette.secondClass,
        'competition': FeaturePalette.competition,
        'jhRead': FeaturePalette.jhRead,
        'libraryEdu': FeaturePalette.libraryEdu,
        'dataCenter': FeaturePalette.dataCenter,
        'dashboard': FeaturePalette.dashboard,
        'electricity': FeaturePalette.electricity,
        'netFee': FeaturePalette.netFee,
        'networkServiceOk': FeaturePalette.networkServiceOk,
        'networkServiceStop': FeaturePalette.networkServiceStop,
        'myMail': FeaturePalette.myMail,
        'zongce': FeaturePalette.zongce,
        'scoreEstimate': FeaturePalette.scoreEstimate,
        'scoreEstimateFinal': FeaturePalette.scoreEstimateFinal,
        'scoreEstimatePending': FeaturePalette.scoreEstimatePending,
        'tice': FeaturePalette.tice,
        'materials': FeaturePalette.materials,
        'calendar': FeaturePalette.calendar,
        'rules': FeaturePalette.rules,
        'leave': FeaturePalette.leave,
        'guidGuide': FeaturePalette.guidGuide,
        'liveClass': FeaturePalette.liveClass,
        'reschedule': FeaturePalette.reschedule,
        'makeUpClass': FeaturePalette.makeUpClass,
        'classCancelled': FeaturePalette.classCancelled,
        'calendarHoliday': FeaturePalette.calendarHoliday,
        'calendarMakeup': FeaturePalette.calendarMakeup,
        'calendarEvent': FeaturePalette.calendarEvent,
        'cxstar': FeaturePalette.cxstar,
        'publicQuery': FeaturePalette.publicQuery,
        'courseSelection': FeaturePalette.courseSelection,
        'imsSession': FeaturePalette.imsSession,
        'deadlineOnline': FeaturePalette.deadlineOnline,
        'deadlineHomework': FeaturePalette.deadlineHomework,
        'deadlineExam': FeaturePalette.deadlineExam,
        'deadlineOther': FeaturePalette.deadlineOther,
        'deadlineSoon': FeaturePalette.deadlineSoon,
        'deadlineOverdue': FeaturePalette.deadlineOverdue,
        'deadlineDone': FeaturePalette.deadlineDone,
      };

      // 短路（明度 ≥ 0.62 原样返回）的色不能「变好」——它根本没被改。
      // 这里把「原样返回」单独记账，再断言**唯一**一个「原样返回且仍 < 4.5:1」的例外。
      final shortCircuited = <String>[];
      palette.forEach((name, light) {
        final dark = featureTone(light);
        expect(
          _contrast(dark, card),
          greaterThanOrEqualTo(3.0),
          reason: '$name 在深色卡片底上不足 3:1（图标 / 大字的下限）',
        );
        expect(_contrast(dark, surface), greaterThanOrEqualTo(3.0));
        if (dark == light) {
          shortCircuited.add(name);
          return;
        }
        if (_contrast(light, card) < 4.5) {
          expect(
            _contrast(dark, card),
            greaterThan(_contrast(light, card)),
            reason: '$name 原本不足 4.5:1，提亮后必须真的变好',
          );
        }
      });

      // 短路组的 4 个色本来就够亮（≥ 6.5:1），只有 `scoreEstimate` 停在 4.13:1 ——
      // 它 ≥ 3:1（图标 / 大字可用），是用户在预览里看过并接受的取值。
      // 把名单写死：将来谁改了短路阈值，这里会立刻红。
      expect(
        shortCircuited.where((n) => _contrast(palette[n]!, card) < 4.5),
        ['scoreEstimate', 'deadlineHomework'],
        reason: '「原样返回且仍不足 4.5:1」只允许 scoreEstimate / deadlineHomework 两个（4.13:1）',
      );
    });

    testWidgets('onAccent：压在强调色实心底上的前景，深色下必须 ≥ 4.5:1（浅色恒白）', (tester) async {
      // 这一类缺陷很隐蔽：角标 / 选中态 chip 的底是**功能色实心**，
      // 深色下被 featureTone 提亮成亮底，而前景若写死 Colors.white 会掉到
      // 1.3–2.9:1（实测 makeUpClass 2.08 / reschedule 2.93 / deadlineOnline ~1.3）。
      late Color Function(Color) onLight;
      late Color Function(Color) onDark;
      // ⚠ 必须**同一帧里各挂一棵 `Theme`**，不能靠「先 pump 浅色再 pump 深色」——
      // `MaterialApp.home` 只在首次生成路由时被消费，第二次 pumpWidget 不会用新的
      // `home` 重建那棵子树，闭包里的 context 会一直是浅色主题的
      // （症状：深色分支静默返回白字，断言以「浅色的对比度」失败）。
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              Theme(
                data: appLightTheme,
                child: Builder(
                  builder: (c) {
                    onLight = (bg) => AppColors.onAccent(c, bg);
                    return const SizedBox();
                  },
                ),
              ),
              Theme(
                data: appDarkTheme,
                child: Builder(
                  builder: (c) {
                    onDark = (bg) => AppColors.onAccent(c, bg);
                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        ),
      );

      // 实际会当「实心底」用的那批（调课角标 / 补课角标 / 停课角标 /
      // 截止日期类型 chip / 主题红实心圆 …）。
      final fills = <String, Color>{
        'cardAccent': FeaturePalette.cardAccent,
        'reschedule': FeaturePalette.reschedule,
        'makeUpClass': FeaturePalette.makeUpClass,
        'classCancelled': FeaturePalette.classCancelled,
        'deadlineOnline': FeaturePalette.deadlineOnline,
        'deadlineHomework': FeaturePalette.deadlineHomework,
        'deadlineExam': FeaturePalette.deadlineExam,
        'deadlineOther': FeaturePalette.deadlineOther,
        'deadlineSoon': FeaturePalette.deadlineSoon,
        'deadlineOverdue': FeaturePalette.deadlineOverdue,
        'deadlineDone': FeaturePalette.deadlineDone,
      };

      for (final e in fills.entries) {
        // 浅色恒定白：浅色是逐像素冻结的基线，不许「顺手优化」成按亮度择字。
        expect(
          onLight(e.value),
          const Color(0xFFFFFFFF),
          reason: '${e.key}：浅色下 onAccent 必须恒为白（浅色零漂移）',
        );
        // 深色：底被提亮 → 择字后必须真的读得清。
        // 例外：`deadlineHomework` 就是 `scoreEstimate`(#536DFE)，明度恰好落在
        // 「白与黑都够不到 4.5」的中段（白 4.24 / 黑 4.10，理论最大 4.17），
        // 与它对 `scoreEstimate` 的既有裁定一致 → 只要求 ≥ 4:1。
        final floor = e.key == 'deadlineHomework' ? 4.0 : 4.5;
        final bg = featureTone(e.value);
        expect(
          _contrast(onDark(bg), bg),
          greaterThanOrEqualTo(floor),
          reason: '${e.key}：深色下压在提亮后的实心底上的前景读不了（$bg）',
        );
      }

      // 固定强调色：品牌色不参与 featureTone 提亮，深色主题红是 onPrimary 那一档
      // → **直接按原值断言，别套 featureTone**。
      // 这几个是「hover / 激活时背景 = 该入口自己的强调色」的前景，曾用
      // `estimateBrightnessForColor` 择字，结果把深色亮红判成暗底给了白字
      // （白 2.79:1 vs 深字 6.25:1）—— 正是本组要守住的回归。
      for (final e in <String, Color>{
        'brandRed #F2555A': const Color(0xFFF2555A),
        'wechatGreen #14C468': const Color(0xFF14C468),
        'wecomBlue #73A9EC': const Color(0xFF73A9EC),
        'brandRedLight #C3282E': const Color(0xFFC3282E),
      }.entries) {
        expect(
          onLight(e.value),
          const Color(0xFFFFFFFF),
          reason: '${e.key}：浅色下 onAccent 必须恒为白（浅色零漂移）',
        );
        expect(
          _contrast(onDark(e.value), e.value),
          greaterThanOrEqualTo(4.5),
          reason: '${e.key}：深色下压在自身实心底上的前景读不了',
        );
      }

      // 深色主题红实心圆同理（校历「今天」）。
      expect(
        _contrast(appDarkScheme.onPrimary, appDarkScheme.primary),
        greaterThanOrEqualTo(4.5),
        reason: '深色下 onPrimary 必须压在亮红 #F2555A 上读得清（白字只有 3.0:1）',
      );
    });

    test('源码守卫：压在强调色实心底上的前景不得再用 estimateBrightnessForColor', () {
      // 这类缺陷在 widget 测试里看不见 —— 要真的 hover / 激活才渲染那支前景
      // （曾实测：深色亮红被 estimateBrightnessForColor 判成「暗底」→
      // 取白字 2.79:1，而深字 6.25:1）→ 只能守源码。
      for (final path in [
        'lib/features/auth/presentation/login_screen.dart',
        'lib/features/qr_login/presentation/widgets/unified_mfa_dialog.dart',
      ]) {
        final src = File(path).readAsStringSync();
        // ⚠ 匹配**带括号的调用**，别匹配裸名字 —— 说明为什么不能用它的注释里
        // 就写着 `ThemeData.estimateBrightnessForColor`（本守卫第一版因此误报）。
        expect(
          src.contains('ThemeData.estimateBrightnessForColor('),
          isFalse,
          reason: '$path：该函数判据太钝，改用 AppColors.onAccent（按实测对比度择字）',
        );
        expect(
          src.contains('AppColors.onAccent('),
          isTrue,
          reason: '$path：压在强调色实心底上的前景应走 AppColors.onAccent',
        );
      }
    });

    test('FeatureColors：浅色 = 原值，深色 = 提亮档', () {      expect(FeatureColors.light.schedule, FeaturePalette.schedule);
      expect(
        FeatureColors.dark.schedule,
        featureTone(FeaturePalette.schedule),
      );
      expect(FeatureColors.dark.cardAccent, const Color(0xFFF2555A));
      expect(FeatureColors.light.cardAccent, FeaturePalette.cardAccent);
      expect(FeatureColors.forBrightness(Brightness.dark).grade, featureTone(FeaturePalette.grade));
      expect(FeatureColors.forBrightness(Brightness.light).grade, FeaturePalette.grade);
    });
  });

  group('④ 外观偏好：默认跟随系统 + 落盘 + 设置页入口', () {
    test('themeModeFromName 容错（空 / 乱码 → null）', () {
      expect(themeModeFromName('system'), ThemeMode.system);
      expect(themeModeFromName('light'), ThemeMode.light);
      expect(themeModeFromName('dark'), ThemeMode.dark);
      expect(themeModeFromName(null), isNull);
      expect(themeModeFromName(''), isNull);
      expect(themeModeFromName('DARK'), isNull);
      expect(themeModeFromName('1'), isNull);
    });

    test('默认跟随系统；save 后落盘且可被新实例读回', () async {
      final store = ThemeModeStore();
      expect(store.mode, ThemeMode.system, reason: '首装必须默认跟随系统');
      await store.ensureLoaded();
      expect(store.mode, ThemeMode.system);

      await store.save(ThemeMode.dark);
      expect(store.mode, ThemeMode.dark);
      expect(Hive.box<String>(themePrefsBoxName).get('themeMode'), 'dark');

      // 新实例（= 下次启动）读回同一个值。
      final again = ThemeModeStore();
      await again.ensureLoaded();
      expect(again.mode, ThemeMode.dark);

      // 清回默认，避免影响同进程里的其它测试。
      await again.save(ThemeMode.system);
      expect(Hive.box<String>(themePrefsBoxName).get('themeMode'), 'system');
    });

    test('save 只通知一次、同值不重复通知', () async {
      final store = ThemeModeStore();
      await store.ensureLoaded();
      var notifications = 0;
      store.addListener(() => notifications++);
      await store.save(ThemeMode.light);
      expect(notifications, 1);
      await store.save(ThemeMode.light); // 同值 → 直接返回
      expect(notifications, 1);
      await store.save(ThemeMode.system);
      expect(notifications, 2);
    });

    test('ensureLoaded 幂等（重复调用不重复读盘 / 不抛）', () async {
      final store = ThemeModeStore();
      await Future.wait([store.ensureLoaded(), store.ensureLoaded()]);
      await store.ensureLoaded();
      expect(store.mode, ThemeMode.system);
    });

    test('分节枚举里有「外观」，且排在第一节', () {
      expect(SettingsSection.appearance.label, '外观');
      expect(SettingsSection.values.first, SettingsSection.appearance);
    });
  });

  group('⑤ 设置页「外观」节 + MaterialApp 真的跟着切', () {
    // ⚠⚠ **本组内各例的顺序是有讲究的，别随手调换。**
    //
    // `Hive` 的 `openBox` / `box.put` 都是**真异步 I/O**。`testWidgets` 跑在假异步区里，
    // 那里发起的真实 I/O **永远不会完成**，而 Hive 对同一个 box 的打开与写入是「单飞」的
    // （内部挂着一个未完成的 future / 写锁）。于是：
    //
    //   「点某一档」这种**在假异步区里触发 `save()`** 的用例，会永久占住 `themePrefs`
    //   的写锁 → 之后**任何**例子里的 `store.save(...)` 都会一直等它，
    //   连 `tester.runAsync` 也救不回来（照样等到 `pumpAndSettle` 的 10 分钟上限，
    //   报 "did not complete"）。
    //
    // 所以顺序必须是：**只要挂载、不写盘的（①②）→ 在 `runAsync` 里写盘的（③④）→
    // 真正点按触发写盘的（⑤）放最后**。反过来放，整份测试会挂死。
    // （实测：单跑 ③④ 通过；一旦前面有例子点过档位，③ 必挂。）
    Widget settingsApp() => const ProviderScope(
      child: MaterialApp(home: SettingsScreen()),
    );

    testWidgets('三档都在，默认选中「跟随系统」', (tester) async {
      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(settingsApp());
      await tester.pumpAndSettle();

      expect(find.text('外观'), findsWidgets); // 节标题
      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.text('浅色'), findsOneWidget);
      expect(find.text('深色'), findsOneWidget);

      // 默认「跟随系统」被选中（三档的图标只有一个是 checked）。
      final checked = find.byIcon(Icons.radio_button_checked);
      expect(checked, findsWidgets);
      final systemRow = find.ancestor(
        of: find.text('跟随系统'),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: systemRow, matching: find.byIcon(Icons.radio_button_checked)),
        findsOneWidget,
        reason: '首装默认必须是「跟随系统」',
      );
    });

    testWidgets('MaterialApp 取到偏好 → 深色真的生效', (tester) async {
      final store = ThemeModeStore();
      // 落盘 / 读盘一律包 `tester.runAsync`（见本组开头的说明）。
      await tester.runAsync(() async {
        await store.ensureLoaded();
        await store.save(ThemeMode.dark);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [themeModeStoreProvider.overrideWith((ref) => store)],
          child: MaterialApp(
            theme: appLightTheme,
            darkTheme: appDarkTheme,
            themeMode: store.mode,
            home: Builder(
              builder: (context) => Text(
                '亮度=${Theme.of(context).brightness}',
                textDirection: TextDirection.ltr,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('亮度=Brightness.dark'), findsOneWidget);

      await tester.runAsync(() => store.save(ThemeMode.light));
      await tester.pumpAndSettle();
      // 直接把 themeMode 喂进 MaterialApp 时不会自动重建 —— 这里只验证 store 确实切了。
      expect(store.mode, ThemeMode.light);
      await tester.runAsync(() => store.save(ThemeMode.system));
    });

    testWidgets('themeModeStoreProvider 的变更会驱动 rebuild（唯一入口）', (tester) async {
      final store = ThemeModeStore();
      await tester.runAsync(() async {
        await store.ensureLoaded();
        await store.save(ThemeMode.light);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [themeModeStoreProvider.overrideWith((ref) => store)],
          child: MaterialApp(
            theme: appLightTheme,
            darkTheme: appDarkTheme,
            home: Consumer(
              builder: (context, ref, _) {
                final mode = ref.watch(themeModeStoreProvider).mode;
                return MaterialApp(
                  theme: appLightTheme,
                  darkTheme: appDarkTheme,
                  themeMode: mode,
                  home: Builder(
                    builder: (c) => Text(
                      '亮度=${Theme.of(c).brightness}',
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('亮度=Brightness.light'), findsOneWidget);

      await tester.runAsync(() => store.save(ThemeMode.dark));
      await tester.pumpAndSettle();
      expect(find.text('亮度=Brightness.dark'), findsOneWidget);

      await tester.runAsync(() => store.save(ThemeMode.system));
    });

    // ⚠ 必须放最后：这一例会点档位，从而在假异步区里发起一次永不完成的 `box.put`
    //   → 永久占住 `themePrefs` 的写锁（见本组开头）。
    testWidgets('点某一档真的写进偏好（放最后，见本组开头说明）', (tester) async {
      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(settingsApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('themeModeOption-dark')));
      await tester.pumpAndSettle();

      expect(Hive.box<String>(themePrefsBoxName).get('themeMode'), 'dark');
      final darkRow = find.ancestor(
        of: find.text('深色'),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: darkRow, matching: find.byIcon(Icons.radio_button_checked)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('themeModeOption-system')));
      await tester.pumpAndSettle();
      expect(Hive.box<String>(themePrefsBoxName).get('themeMode'), 'system');
    });
  });

  group('⑥ AppColors 的错误红三态：浅色 = 原样，深色 = 深红实心件', () {
    /// 同一帧各挂一棵 `Theme` —— **不要**「先 pump 浅色再 pump 深色」：
    /// `MaterialApp.home` 只在首次生成路由时被消费，第二次 `pumpWidget` 不会用新的
    /// `home` 重建那棵子树，闭包里的 context 会一直停在浅色主题。
    Future<({Color fill, Color onFill, Color border})> probe(
      WidgetTester tester,
      ThemeData theme,
    ) async {
      late Color fill;
      late Color onFill;
      late Color border;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              fill = AppColors.errorFill(context);
              onFill = AppColors.onErrorFill(context);
              border = AppColors.errorBorder(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return (fill: fill, onFill: onFill, border: border);
    }

    testWidgets('浅色：三态逐像素 = 改动前的写死值（冻结基线）', (tester) async {
      final r = await probe(tester, appLightTheme);
      expect(r.fill, appLightScheme.error); // 原本就是 colorScheme.error
      expect(r.onFill, appLightScheme.onError);
      expect(r.border, appLightScheme.error.withValues(alpha: 0.7));
      // 浅色侧不许变成深红。
      expect(r.fill, isNot(AppLadder.darkErrorFill));
      expect(r.onFill, const Color(0xFFFFFFFF));
    });

    testWidgets('深色：实心件 = 深红 #C62828 + 白字，描边 = 不透明深红（不是淡红叠色）', (tester) async {
      final r = await probe(tester, appDarkTheme);
      expect(r.fill, const Color(0xFFC62828));
      expect(r.onFill, const Color(0xFFFFFFFF));
      expect(r.border, const Color(0xFFC62828));
      // 描边必须**不透明**：深色下 `error@70%` 混出来的是 #AE3D40（2.93:1）。
      expect(r.border.a, 1.0);
      expect(r.fill, isNot(appDarkScheme.error));
      expect(r.border, isNot(appDarkScheme.error.withValues(alpha: 0.7)));
    });

    test('源码守卫：成绩页的红实心件 / 红描边不得再直接吃 colorScheme.error', () {
      // 亮红 #EE4C50 是**当文字用**的档；实心件与描边必须走 AppColors。
      final src = File(
        'lib/features/ims/grades/presentation/grades_screen.dart',
      ).readAsStringSync();
      expect(src.contains('AppColors.errorFill(context)'), isTrue);
      expect(src.contains('AppColors.onErrorFill(context)'), isTrue);
      expect(src.contains('AppColors.errorBorder(context)'), isTrue);
      // 不许再有「error @ 70%」当框线。
      expect(src.contains('colorScheme.error.withValues(alpha: 0.7)'), isFalse);
      // 表头底色不许再直接吃 error。
      expect(src.contains('headerBgColor: theme.colorScheme.error'), isFalse);
    });

    test('源码守卫：其余「红实心件」也都换了深红档（改了底就必须改前景）', () {
      // 2026-09-16 全仓清点出的实心红件（按钮底 / 头像底），全部走 AppColors。
      // 漏改前景 = 深字压在深红上（FilledButton 默认前景是 onPrimary）。
      for (final path in const [
        'lib/features/ims/course_selection/presentation/selection_result_view.dart',
        'lib/features/network_service/presentation/network_common.dart',
        'lib/features/network_service/presentation/network_services_screen.dart',
        'lib/features/ims/student_info/presentation/account_screen.dart',
        'lib/shared/widgets/account_avatar.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('AppColors.errorFill(context)'),
          isTrue,
          reason: '$path 的实心红件应走 AppColors.errorFill',
        );
        expect(
          src.contains('AppColors.onErrorFill(context)'),
          isTrue,
          reason: '$path 压在深红底上的前景应走 AppColors.onErrorFill',
        );
        expect(
          src.contains('backgroundColor: scheme.error'),
          isFalse,
          reason: '$path 不该再有亮红当实心底',
        );
      }
      // 账号头像：底与前景是一对，不该只有一半。
      final avatar = File('lib/shared/widgets/account_avatar.dart').readAsStringSync();
      expect(avatar.contains('scheme.onError'), isFalse);
    });
  });

  group('⑦ 半透明淡底 / 淡描边：深色抬 alpha，浅色逐像素冻结', () {
    /// 把带 alpha 的前景压到不透明底色上（与 Flutter 的混合口径一致）。
    Color over(Color fg, Color bg) {
      double ch(double f, double b) => f * fg.a + b * (1 - fg.a);
      return Color.from(
        alpha: 1,
        red: ch(fg.r, bg.r),
        green: ch(fg.g, bg.g),
        blue: ch(fg.b, bg.b),
      );
    }

    /// 同一帧各挂一棵 `Theme`（理由同组⑥：`MaterialApp.home` 只被消费一次）。
    Future<({Color fill, Color border})> probe(
      WidgetTester tester,
      ThemeData theme,
      Color accent, {
      double fillAlpha = 0.06,
      double borderAlpha = 0.35,
    }) async {
      late Color fill;
      late Color border;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              fill = AppColors.tint(context, accent, fillAlpha);
              border = AppColors.tintBorder(context, accent, borderAlpha);
              return const SizedBox();
            },
          ),
        ),
      );
      return (fill: fill, border: border);
    }

    test('换算表：淡底 ×3.5、描边 ×1.2，并夹在安全区间内', () {
      // 淡底：0.04 最轻 … 0.06 起逐步逼近封顶值。
      expect(AppLadder.darkTintAlpha(0.04), closeTo(0.14, 1e-9));
      expect(AppLadder.darkTintAlpha(0.05), closeTo(0.175, 1e-9));
      expect(AppLadder.darkTintAlpha(0.06), closeTo(0.21, 1e-9));
      expect(AppLadder.darkTintAlpha(0.02), closeTo(0.14, 1e-9)); // 14% 下限
      // 封顶 = 全应用统一的深色淡底上限（= statusFill 的深色档）。
      expect(AppLadder.darkTintAlpha(0.07), AppLadder.darkSoftAlpha);
      expect(AppLadder.darkTintAlpha(0.08), AppLadder.darkSoftAlpha);
      expect(AppLadder.darkTintAlpha(0.09), AppLadder.darkSoftAlpha);
      expect(AppLadder.darkTintAlpha(0.12), AppLadder.darkSoftAlpha);
      expect(AppLadder.darkSoftAlpha, 0.22);
      // **不许倒挂**：浅色越浓的，深色只能不淡于它（`statusFill` 的 0.12 档
      // 与 tint 的封顶必须是同一个值，否则浅色 8% 会比浅色 12% 更浓）。
      var prev = -1.0;
      for (final a in const [0.02, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.12, 0.2]) {
        final d = AppLadder.darkTintAlpha(a);
        expect(d, greaterThanOrEqualTo(prev), reason: '轻重次序不许颠倒（$a）');
        expect(d, lessThanOrEqualTo(AppLadder.darkSoftAlpha));
        prev = d;
      }
      // 描边本来就比底色浓，倍率必须小得多。
      expect(AppLadder.darkBorderAlpha(0.28), closeTo(0.336, 1e-9));
      expect(AppLadder.darkBorderAlpha(0.3), closeTo(0.36, 1e-9));
      expect(AppLadder.darkBorderAlpha(0.35), closeTo(0.42, 1e-9));
      expect(AppLadder.darkBorderAlpha(0.5), lessThan(0.7)); // 有上限，不会冲到不透明
      // 下限 0.30：有一批面板是「淡底 5% + 淡框 16%」，底抬上去之后
      // 框若停在 16% 会被自己的底吞掉（浅色下框是底的 3.2 倍浓）。
      expect(AppLadder.darkBorderAlpha(0.16), closeTo(0.30, 1e-9));
      expect(
        AppLadder.darkBorderAlpha(0.16),
        greaterThan(AppLadder.darkTintAlpha(0.05)),
        reason: '「淡底 + 淡框」的面板，框必须比底浓，否则框线消失',
      );
    });

    testWidgets('浅色：tint / tintBorder 就是调用方原来的 withValues（冻结基线）', (tester) async {
      const accent = Color(0xFFC3282E);
      for (final a in const [0.04, 0.05, 0.06, 0.07, 0.08, 0.09]) {
        final r = await probe(tester, appLightTheme, accent, fillAlpha: a);
        expect(r.fill, accent.withValues(alpha: a));
      }
      for (final a in const [0.28, 0.3, 0.35]) {
        final r = await probe(tester, appLightTheme, accent, borderAlpha: a);
        expect(r.border, accent.withValues(alpha: a));
      }
      // 浅色侧不许被「深色换算」污染。
      final r = await probe(tester, appLightTheme, accent);
      expect(r.fill.a, 0.06);
      expect(r.border.a, 0.35);
    });

    testWidgets('深色：同一次调用被抬到等效 alpha', (tester) async {
      const accent = Color(0xFFC3282E);
      final r = await probe(tester, appDarkTheme, accent);
      expect(r.fill.a, AppLadder.darkTintAlpha(0.06));
      expect(r.border.a, AppLadder.darkBorderAlpha(0.35));
      // 色相 / 饱和不许被换算动过（只是 alpha 变了）。
      expect(r.fill.r, accent.r);
      expect(r.fill.g, accent.g);
      expect(r.fill.b, accent.b);
      // statusFill 的深色档 = 同一个封顶值（结构性一致，不是巧合）。
      late Color status;
      await tester.pumpWidget(
        MaterialApp(
          theme: appDarkTheme,
          home: Builder(
            builder: (context) {
              status = AppColors.statusFill(context, accent);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(status.a, AppLadder.darkSoftAlpha);
    });

    testWidgets('共享淡底 token 也跟主题走（appCardAccentSoft / FeatureColors.cardAccentSoft）', (tester) async {
      // 首页仪表盘三张卡片的图标底板走 appCardAccentSoft —— 它曾经在深色下
      // 也是 0.10，图标底板整个看不见。
      // ⚠ 同一帧各挂一棵 `Theme`：**不能**「先 pump 浅色，再 pump 深色」——
      // `MaterialApp.home` 只在首次生成路由时被消费（见组⑥说明）。
      late Color lightCardSoft;
      late Color darkCardSoft;
      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: Column(
            children: [
              Theme(
                data: appLightTheme,
                child: Builder(
                  builder: (context) {
                    lightCardSoft = appCardAccentSoft(context);
                    return const SizedBox();
                  },
                ),
              ),
              Theme(
                data: appDarkTheme,
                child: Builder(
                  builder: (context) {
                    darkCardSoft = appCardAccentSoft(context);
                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        ),
      );
      expect(lightCardSoft.a, 0.10); // 浅色冻结
      expect(darkCardSoft.a, AppLadder.darkSoftAlpha);
      // 实例色表的同一档也必须跟着走（桌面小组件/拿不到 context 的 helper 用它）。
      expect(FeatureColors.light.cardAccentSoft.a, 0.10);
      expect(FeatureColors.dark.cardAccentSoft.a, AppLadder.darkSoftAlpha);
    });

    testWidgets('不变式：深色淡底叠在卡片上必须与卡片分得开，且压得住正文', (tester) async {
      const card = AppLadder.darkCard; // #1A1A1A
      const text = Color(0xFFEBEBEB); // darkOnSurface
      for (final accent in const [
        Color(0xFFF2555A), // primary（深色强调色）
        Color(0xFFEE4C50), // error（深色亮红档）
      ]) {
        final dark = await probe(tester, appDarkTheme, accent);
        final tinted = over(dark.fill, card);
        expect(
          _contrast(tinted, card),
          greaterThan(1.15),
          reason: '深色淡底必须与卡片底分得开（$accent）',
        );
        expect(
          _contrast(text, tinted),
          greaterThan(4.5),
          reason: '压在这个淡底上的正文仍须 ≥4.5:1（$accent）',
        );
        // 缺陷锚点：**没抬 alpha 的旧写法**在深色下与卡片底几乎不可分。
        final before = over(accent.withValues(alpha: 0.06), card);
        expect(
          _contrast(before, card),
          lessThan(1.15),
          reason: '旧写法（6% 直接叠深底）应当是不合格的 —— 这条断言是缺陷的证据',
        );
      }
    });

    test('源码守卫：浅色 alpha 不再是 0.12 的「红淡底」必须走 tint / tintBorder', () {
      const files = [
        'lib/features/electricity/presentation/electricity_screen.dart',
        'lib/features/leave/presentation/leave_detail_screen.dart',
        'lib/features/leave/presentation/leave_screen.dart',
        'lib/features/library_edu/presentation/tsgxs_exam_screen.dart',
        'lib/features/my_mail/presentation/my_mail_screen.dart',
        'lib/features/network_service/presentation/network_common.dart',
        'lib/features/net_fee/presentation/net_fee_screen.dart',
        'lib/features/platform_guid/presentation/guid_guide_screen.dart',
      ];
      for (final path in files) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('AppColors.tint('),
          isTrue,
          reason: '$path 的警示面板淡底应走 AppColors.tint',
        );
      }
      // 报警面板都用 tintBorder；guid 页只有底色，没有框线。
      for (final path in files.where(
        (p) => !p.contains('guid_guide_screen'),
      )) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('AppColors.tintBorder('),
          isTrue,
          reason: '$path 的警示面板框线应走 AppColors.tintBorder',
        );
      }
    });

    test('源码守卫：lib/features 与 lib/shared 下不许再有低 alpha 的红淡底直接吃 colorScheme.error', () {
      // 深色下 6% 的红叠在 #1A1A1A 上 ≈ #201A1A —— 等于没画。
      final offenders = <String>[];
      for (final dir in const ['lib/features', 'lib/shared']) {
        for (final e in Directory(dir).listSync(recursive: true)) {
          if (e is! File || !e.path.endsWith('.dart')) continue;
          final src = e.readAsStringSync();
          if (src.contains('error.withValues(alpha: 0.0')) {
            offenders.add(e.path.replaceAll(r'\', '/'));
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '这些文件的红色淡底还没收口到 AppColors.tint：$offenders',
      );
    });
  });

  group('⑧ 中性淡描边 / 分隔线：`withValues` 是「替换」不是「相乘」（2026-09-17）', () {
    // 用户原话：「深色模式桌面端左侧导航栏底部固定项最顶部的分割线太亮」。
    // 成因：深色下 `outlineVariant` = `0x1AFFFFFF`（10% 白，**自带 alpha**），
    // `.withValues(alpha: 0.6)` 把 alpha **替换**成 0.6 → 60% 白（叠在侧栏 #1A1A1A
    // 上混成 `#A3A3A3`，窗口截图逐行扫描实测）。浅色下 `outlineVariant` 是**不透明**
    // 暖灰 `#D8C2C0` → 同一写法才是「淡线」的本意，所以这个 bug 只出现在深色侧。

    Future<(BuildContext, BuildContext)> pumpBoth(WidgetTester tester) async {
      final ctx = <String, BuildContext>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              for (final entry in [
                ('light', appLightTheme),
                ('dark', appDarkTheme),
              ])
                Theme(
                  data: entry.$2,
                  child: Builder(
                    builder: (c) {
                      ctx[entry.$1] = c;
                      return const SizedBox();
                    },
                  ),
                ),
            ],
          ),
        ),
      );
      return (ctx['light']!, ctx['dark']!);
    }

    testWidgets('hairline：浅色逐值冻结，深色落到 10% 白基准', (tester) async {
      final (light, dark) = await pumpBoth(tester);

      for (final a in const [0.5, 0.6, 0.7, 0.9]) {
        expect(
          AppColors.hairline(light, a),
          appLightScheme.outlineVariant.withValues(alpha: a),
          reason: '浅色 $a 档必须与改动前的裸写法逐像素相同',
        );
        expect(
          _rgb(AppColors.hairline(light, a)),
          _rgb(appLightScheme.outlineVariant),
          reason: '浅色只动 alpha，不该动 RGB（暖灰 #D8C2C0）',
        );
      }

      // 深色：0.6 档 = `outlineVariant` 原值（10% 白）；其余按同一稀释比例缩。
      expect(AppColors.hairline(dark, 0.6), AppLadder.darkOutlineVariant);
      for (final (a, factor) in const [(0.5, 5 / 6), (0.7, 7 / 6), (0.9, 1.5)]) {
        expect(
          AppColors.hairline(dark, a).a,
          closeTo(0.102 * factor, 0.002),
          reason: '深色 $a 档',
        );
      }
      expect(
        AppColors.hairline(dark).a,
        lessThan(0.15),
        reason: '默认档也不许是亮白线',
      );
    });

    testWidgets('不变式：深色发丝线与底「几乎同深」；旧的 60% 白是刺眼白线', (tester) async {
      final (light, dark) = await pumpBoth(tester);
      final card = AppLadder.darkCard;
      Color over(Color line, Color bg) => Color.alphaBlend(line, bg);

      final oldLine = over(
        AppLadder.darkOutlineVariant.withValues(alpha: 0.6),
        card,
      );
      final newLine = over(AppColors.hairline(dark, 0.6), card);
      final lightLine = over(AppColors.hairline(light, 0.6), AppLadder.lightCard);

      // 反向断言：旧写法确实是白线（这就是用户看到的那根）—— 谁把它改回去，这里就红。
      expect(_contrast(oldLine, card), greaterThan(4.0));
      expect(
        _contrast(newLine, card),
        lessThan(_contrast(oldLine, card) - 3),
        reason: '新档必须比旧写法暗一个量级',
      );
      // 新档与**浅色下同一根线**同档：都是「看得见但压不住内容」的发丝线。
      expect(_contrast(lightLine, AppLadder.lightCard), inInclusiveRange(1.2, 1.5));
      expect(_contrast(newLine, card), inInclusiveRange(1.2, 1.5));
    });

    testWidgets('侧栏底部固定区上方那条线：深色 = 10% 白发丝线', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appDarkTheme,
          home: const Scaffold(
            body: HomeSidebar(
              entries: [],
              footer: SizedBox(height: HomeSidebar.footerRowHeight),
            ),
          ),
        ),
      );

      final divider = tester.widget<Divider>(find.byType(Divider));
      final color = divider.color!;
      expect(
        color,
        AppLadder.darkOutlineVariant,
        reason: '深色下必须走 AppColors.hairline（10% 白），不是 60% 白',
      );
      expect(
        _contrast(Color.alphaBlend(color, AppLadder.darkCard), AppLadder.darkCard),
        lessThan(1.5),
      );
    });

    test('源码守卫：lib/features 与 lib/shared 下不许再有 outlineVariant 裸稀释', () {
      // `scheme.outlineVariant.withValues(alpha: …)` 在深色下会把 10% 白放大成
      // 50~90% 白。唯一正确写法 = `AppColors.hairline(context, 原浅色 alpha)`。
      // 注释里可以提这个写法（警示后人），所以只扫 `//` 之前的代码部分。
      final offenders = <String>[];
      for (final dir in const ['lib/features', 'lib/shared']) {
        for (final e in Directory(dir).listSync(recursive: true)) {
          if (e is! File || !e.path.endsWith('.dart')) continue;
          final bad = e
              .readAsStringSync()
              .split('\n')
              .map((line) => line.split('//').first)
              .any(
                (code) =>
                    code.contains('outlineVariant.withValues(alpha:') ||
                    code.contains('outline.withValues(alpha:'),
              );
          if (bad) offenders.add(e.path.replaceAll(r'\', '/'));
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '这些文件的淡描边 / 分隔线还没收口到 AppColors.hairline：$offenders',
      );
    });
  });
}
