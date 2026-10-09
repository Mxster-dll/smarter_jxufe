import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/home/domain/home_card_gap.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_style.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';

/// 主页布局判定守卫（第 1 条：电脑端主页可选宫格视图与左侧导航栏视图）。
///
/// 判定集中在 [homeUsesSidebarLayout]：用户选了侧栏 **且** 桌面平台 **且**
/// 宽度 ≥ [homeSidebarMinWidth] 才用侧栏，否则一律宫格（手机端永远宫格）。
///
/// 卡片形态判定（用户 2026-10-09 二轮：「我希望 内容区一个卡片、侧栏一个卡片，然后
/// 都是在设置了可选的。可以都不显示为卡片样式」）同在本文件：[HomeCardStyle]
/// 四档 → 哪块画成卡片（`sidebarIsCard` / `contentIsCard` / `anyCard`）。
void main() {
  group('homeUsesSidebarLayout', () {
    test('选了侧栏 + 桌面 + 足够宽 → 侧栏', () {
      expect(
        homeUsesSidebarLayout(
          layout: HomeLayout.sidebar,
          desktop: true,
          width: homeSidebarMinWidth,
        ),
        isTrue,
      );
      expect(
        homeUsesSidebarLayout(
          layout: HomeLayout.sidebar,
          desktop: true,
          width: 1920,
        ),
        isTrue,
      );
    });

    test('选了宫格 → 永远宫格（哪怕窗口很宽）', () {
      expect(
        homeUsesSidebarLayout(
          layout: HomeLayout.grid,
          desktop: true,
          width: 2560,
        ),
        isFalse,
      );
    });

    test('非桌面平台 → 宫格（手机端不出现侧栏）', () {
      expect(
        homeUsesSidebarLayout(
          layout: HomeLayout.sidebar,
          desktop: false,
          width: 1600,
        ),
        isFalse,
      );
    });

    test('窄于阈值 → 宫格', () {
      expect(
        homeUsesSidebarLayout(
          layout: HomeLayout.sidebar,
          desktop: true,
          width: homeSidebarMinWidth - 0.5,
        ),
        isFalse,
      );
    });
  });

  group('homeDesktopPlatform', () {
    test('windows / macOS / linux 是桌面', () {
      for (final name in ['windows', 'macOS', 'linux', 'Windows']) {
        expect(homeDesktopPlatform(name), isTrue, reason: name);
      }
    });

    test('android / ios / fuchsia 不是桌面', () {
      for (final name in ['android', 'ios', 'fuchsia', '']) {
        expect(homeDesktopPlatform(name), isFalse, reason: name);
      }
    });
  });

  group('HomeLayout.fromName', () {
    test('name 往返一致', () {
      for (final value in HomeLayout.values) {
        expect(HomeLayout.fromName(value.name), value);
      }
    });

    test('未知 / 空 / null → 宫格（旧数据不崩）', () {
      expect(HomeLayout.fromName(null), HomeLayout.grid);
      expect(HomeLayout.fromName(''), HomeLayout.grid);
      expect(HomeLayout.fromName('twoColumn'), HomeLayout.grid);
    });

    test('每个形态都有选项名与说明（设置页直接用）', () {
      for (final value in HomeLayout.values) {
        expect(value.label.trim(), isNotEmpty);
        expect(value.description.trim(), isNotEmpty);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 卡片形态（用户 2026-10-09 二轮）。四档 = 两块区域「选 / 不选」的全部组合；
  // 默认**都不显示** —— 老用户升级后观感与改造前一致，不会被动变成卡片。
  // ---------------------------------------------------------------------------
  group('HomeCardStyle', () {
    test('默认是「都不显示」：两块都通栏，且不留卡片缝', () {
      final value = HomeCardStyle.fromName(null);
      expect(value, HomeCardStyle.none);
      expect(value.sidebarIsCard, isFalse);
      expect(value.contentIsCard, isFalse);
      expect(value.anyCard, isFalse);
    });

    test('name 往返一致（落盘 → 还原）', () {
      for (final value in HomeCardStyle.values) {
        expect(HomeCardStyle.fromName(value.name), value, reason: value.name);
      }
    });

    test('未知 / 空 → 都不显示（旧数据不崩）', () {
      expect(HomeCardStyle.fromName(''), HomeCardStyle.none);
      expect(HomeCardStyle.fromName('floating'), HomeCardStyle.none);
    });

    test('每一档只点亮它该点亮的区域', () {
      expect(HomeCardStyle.sidebar.sidebarIsCard, isTrue);
      expect(HomeCardStyle.sidebar.contentIsCard, isFalse);
      expect(HomeCardStyle.content.sidebarIsCard, isFalse);
      expect(HomeCardStyle.content.contentIsCard, isTrue);
      expect(HomeCardStyle.both.sidebarIsCard, isTrue);
      expect(HomeCardStyle.both.contentIsCard, isTrue);
    });

    test('anyCard 恒等于「两块里有任意一块是卡片」（决定要不要留那道缝）', () {
      for (final value in HomeCardStyle.values) {
        expect(
          value.anyCard,
          value.sidebarIsCard || value.contentIsCard,
          reason: value.name,
        );
      }
      expect(HomeCardStyle.none.anyCard, isFalse);
      expect(HomeCardStyle.sidebar.anyCard, isTrue);
      expect(HomeCardStyle.content.anyCard, isTrue);
      expect(HomeCardStyle.both.anyCard, isTrue);
    });

    test('每一档都有选项名与说明（设置页直接用）', () {
      for (final value in HomeCardStyle.values) {
        expect(value.label.trim(), isNotEmpty, reason: value.name);
        expect(value.description.trim(), isNotEmpty, reason: value.name);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 卡片间距 a（三轮：「卡片与卡片之间的距离为 2a、卡片与窗口之间的距离为 a」；
  // **十七轮修订**：「我希望现在的卡片与卡片之间的间距不再是 2a，而是 a」）。
  // 派生量与夹取是纯逻辑，全在这一组里守。
  // ---------------------------------------------------------------------------
  group('cardGapMetricsOf', () {
    test('卡片之间 = a、距窗口边 = a（十七轮口径：一值管两处）', () {
      final m = cardGapMetricsOf(6);
      expect(m.edge, 6);
      expect(m.between, 6, reason: '十七轮起两处同值（原来是 2a = 12）');
    });

    test('a 逐档都对（含上下限）', () {
      for (final a in kCardGapStops) {
        final m = cardGapMetricsOf(a);
        expect(m.edge, a, reason: '$a');
        expect(m.between, a, reason: '$a：卡片间距必须与边距同值');
      }
    });

    test('越界 / NaN 一律夹回，绝不抛', () {
      expect(cardGapMetricsOf(-5).edge, kCardGapMin);
      expect(cardGapMetricsOf(999).edge, kCardGapMax);
      // NaN / 无穷没有「夹」的意义 → 一律回落默认值（不是夹到某一端）。
      expect(cardGapMetricsOf(double.nan).edge, kCardGapDefault);
      expect(cardGapMetricsOf(double.infinity).edge, kCardGapDefault);
      expect(cardGapMetricsOf(double.negativeInfinity).edge, kCardGapDefault);
    });

    test('外围补白 ≥ 边距，且给阴影留了落点', () {
      for (final a in kCardGapStops) {
        final m = cardGapMetricsOf(a);
        expect(m.gutter, greaterThan(m.edge), reason: '$a');
        expect(
          m.gutter - m.edge,
          greaterThanOrEqualTo(8),
          reason: '$a：阴影（blur 12 / 视觉半径约 9）必须有地方落',
        );
      }
    });

    test('默认值 = kCardGapDefault（两处都是 8）', () {
      final m = cardGapMetricsOf(kCardGapDefault);
      expect(kCardGapDefault, 8, reason: '十七轮：6 在实心圆角卡之间太挤');
      expect(m.edge, 8);
      expect(m.between, 8);
    });

    test('snapCardGap 吸附到档位（中点取较小那档）', () {
      expect(snapCardGap(3.4), 3);
      expect(snapCardGap(3.6), 4);
      expect(snapCardGap(3.5), 3, reason: '正中点向下取');
      expect(snapCardGap(999), kCardGapMax);
      expect(snapCardGap(-1), kCardGapMin);
      for (final a in kCardGapStops) {
        expect(snapCardGap(a), a, reason: '$a 必须吸附到自己');
      }
    });

    // 用户 2026-10-09 十四轮：「我希望卡片间距可以调整的最小步长应该是 1，现在是 2」。
    // 症状的成因 = 滑杆按每格 1 画刻度、而档位表很稀（`[2,3,4,6,8,…]`）→ 拖到 5 会被
    // 吸附回 4 / 6，看起来就是「步长 2」。所以**档位表必须是 2..24 的连续整数**。
    test('★ 档位表必须是 2..24 的每个整数（步长 1，不许有洞）', () {
      final expected = [
        for (var v = kCardGapMin; v <= kCardGapMax; v += 1) v.toDouble(),
      ];
      expect(
        kCardGapStops,
        expected,
        reason: '缺任何一格都会让滑杆"看起来步长 2"（用户十四轮报的那个 bug）',
      );
      expect(
        kCardGapStops.length,
        23,
        reason: '2..24 含两端共 23 格；滑杆 divisions = 22（段数）→ 23 个刻度，'
            '两者必须同一口径',
      );
      // 每个整数都真的能被滑杆取到（吸附不改值）且落盘能还原。
      for (final a in expected) {
        expect(snapCardGap(a), a, reason: '$a 吸附后必须还是 $a');
        expect(parseCardGap(formatCardGap(a)), a, reason: '$a 落盘往返');
      }
    });

    test('落盘往返：整数文本，脏值回落默认', () {
      for (final a in kCardGapStops) {
        expect(parseCardGap(formatCardGap(a)), a, reason: '$a');
      }
      expect(formatCardGap(6), '6', reason: '别写成 6.0');
      expect(parseCardGap(null), kCardGapDefault);
      expect(parseCardGap(''), kCardGapDefault);
      expect(parseCardGap('abc'), kCardGapDefault);
      expect(parseCardGap(' 8 '), 8, reason: '容忍空白');
      expect(parseCardGap('999'), kCardGapMax, reason: '越界夹回');
    });
  });
}
