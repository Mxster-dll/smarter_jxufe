// 排布模型的**表驱动**测试（2026-10-10 重构的红利）：不 pump 任何 widget，
// 一行一条覆盖「宽度 × 平台 × 风格 × 交换 × 各区在不在」。
//
// 它存在的理由很具体：重构前有两个 bug 只有点开界面才发现 —— ① mac 风格 + 交换三键 →
// 三键整个不可见；② 窄屏下三键跟着动作簇漂到左边。这两条在下面这张表里都是**一眼可读**
// 的断言（"无论怎么组合，controls 都只由偏好决定" / "mac 的顺序倒置不影响风格"）。
import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/design/breakpoints.dart';
import 'package:smarter_jxufe/design/window_chrome/title_bar_model.dart';
import 'package:smarter_jxufe/features/settings/data/window_bar_prefs.dart';

/// 算一次排布（默认：宽屏 1200、桌面、Win 风格、不交换、三区俱全）。
TitleBarLayoutModel compute({
  double width = 1200,
  bool desktop = true,
  WindowButtonsStyle style = WindowButtonsStyle.windows,
  bool swapSides = false,
  bool hasActions = true,
  bool hasBrand = true,
  bool hasHistory = true,
  bool hasSidebarToggle = false,
}) =>
    TitleBarLayoutModel.compute(
      width: width,
      desktop: desktop,
      style: style,
      swapSides: swapSides,
      hasActions: hasActions,
      hasBrand: hasBrand,
      hasHistory: hasHistory,
      hasSidebarToggle: hasSidebarToggle,
    );

void main() {
  group('阈值（Breakpoints.narrow = 600）', () {
    test('599 是窄屏、600 是宽屏（边界取「小于」）', () {
      expect(compute(width: 599).narrow, isTrue);
      expect(compute(width: 600).narrow, isFalse);
    });

    test('阈值就是 Breakpoints.narrow，不是页面那条 900', () {
      expect(Breakpoints.narrow, 600);
    });
  });

  group('三键：任何宽度、任何组合都不许漂', () {
    test('Win 风格默认在右；交换后在左', () {
      expect(compute().controls, TitleBarSlot.right);
      expect(compute(swapSides: true).controls, TitleBarSlot.left);
    });

    test('mac 风格默认在左（mac 惯例）；交换后在右', () {
      expect(
        compute(style: WindowButtonsStyle.mac).controls,
        TitleBarSlot.left,
      );
      expect(
        compute(style: WindowButtonsStyle.mac, swapSides: true).controls,
        TitleBarSlot.right,
      );
    });

    test('★ 窄屏 + 窄到 320、手机平台、有动作有品牌 —— controls 依旧只由偏好决定', () {
      for (final width in <double>[1200, 900, 700, 600, 599, 320]) {
        for (final style in WindowButtonsStyle.values) {
          for (final swap in <bool>[false, true]) {
            final m = compute(
              width: width,
              desktop: false,
              style: style,
              swapSides: swap,
            );
            expect(
              m.controls,
              windowButtonsOnLeft(style: style, swapSides: swap)
                  ? TitleBarSlot.left
                  : TitleBarSlot.right,
              reason: 'width=$width style=$style swap=$swap 时三键漂了',
            );
          }
        }
      }
    });
  });

  group('mac 顺序：只改顺序、不改风格', () {
    test('mac 在左 → 倒置；mac 在右 / Win → 不倒置', () {
      expect(compute(style: WindowButtonsStyle.mac).macOrderReversed, isTrue);
      expect(
        compute(style: WindowButtonsStyle.mac, swapSides: true)
            .macOrderReversed,
        isFalse,
      );
      expect(compute().macOrderReversed, isFalse);
    });
  });

  group('宽屏：中间组占原 logo 位（三键对侧）、动作簇与三键同侧、品牌恒 hidden', () {
    test('默认（Win 在右）', () {
      final m = compute();
      expect(m.actions, TitleBarSlot.right, reason: '与三键同侧紧挨');
      expect(m.center, TitleBarSlot.left, reason: '三键在右 → 中间组占原来 logo 的位置（左）');
      expect(m.brand, TitleBarSlot.hidden, reason: 'logo 显示区已彻底删除（用户 2026-10-10）');
    });

    test('交换后在左：品牌去右、动作簇跟着三键', () {
      final m = compute(swapSides: true);
      expect(m.actions, TitleBarSlot.left);
      expect(m.center, TitleBarSlot.right, reason: '交换后三键在左 → 中间组占原来 logo 的位置（右）');
      expect(m.brand, TitleBarSlot.hidden);
    });

    test('没有动作 / 没有品牌 / 什么都没有时逐项 hidden', () {
      expect(compute(hasActions: false).actions, TitleBarSlot.hidden);
      expect(compute().brand, TitleBarSlot.hidden, reason: '恒 hidden（品牌区已删除）');
      final bare = compute(hasActions: false, hasBrand: false, hasHistory: false);
      expect(bare.center, TitleBarSlot.hidden);
    });
  });

  group('窄屏：无品牌、center 并入 actions（同摆三键对侧）', () {
    test('有动作时：actions 在三键对侧，center 让位', () {
      final m = compute(width: 560);
      expect(m.brand, TitleBarSlot.hidden);
      expect(m.actions, TitleBarSlot.left, reason: '三键在右 → 动作簇在左');
      expect(m.center, TitleBarSlot.hidden, reason: '已并入 actions');
    });

    test('交换后：三键在左 → 合并那一坨去右', () {
      final m = compute(width: 560, swapSides: true);
      expect(m.actions, TitleBarSlot.right);
      expect(m.center, TitleBarSlot.hidden);
    });

    test('没有动作、只有中间组时：由 center 槽位承载，仍摆三键对侧', () {
      final m = compute(width: 560, hasActions: false);
      expect(m.actions, TitleBarSlot.hidden);
      expect(m.center, TitleBarSlot.left);
    });

    test('手机平台（桌面=false）与窄屏同一条路', () {
      final m = compute(width: 1400, desktop: false);
      // 1400 宽在桌面上是「宽屏」，但手机上永远按窄屏那套（品牌不画、中间组并左/右）。
      expect(m.narrow, isFalse, reason: 'narrow 只看宽度');
      expect(m.brand, TitleBarSlot.hidden, reason: '自己绘标题栏时才画；且品牌区已删除');
    });
  });
}
