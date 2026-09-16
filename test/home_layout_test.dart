import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/home/domain/home_layout.dart';

/// 主页布局判定守卫（第 1 条：电脑端主页可选宫格视图与左侧导航栏视图）。
///
/// 判定集中在 [homeUsesSidebarLayout]：用户选了侧栏 **且** 桌面平台 **且**
/// 宽度 ≥ [homeSidebarMinWidth] 才用侧栏，否则一律宫格（手机端永远宫格）。
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
}
