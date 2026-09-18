/// 课表正文让开底部系统导航栏（用户 2026-09-17：「我希望课表适应高度不要包括
/// 底部三键导航的部分」）。
///
/// 背景：课表是**恒适应高度**的（竖版把 12 节铺满内容区、横版可见天平分剩余
/// 高度），而 Flutter 的 `Scaffold` **不会**替 `body` 让出系统导航栏
/// （`scaffold.dart:3187-3190` 把 `minInsets.bottom` 覆写成键盘高度或 0，
/// 系统栏只进 `minViewPadding`）；本应用又是 edge-to-edge（`home_screen.dart`
/// 口径），导航栏盖在内容之上 → 不让位就会把最后一节 / 最后一天盖住。
///
/// 这里既测组件行为（给假的底部内边距，断言正文底边），也守卫课表页的接线
/// （正文必须被 `ScheduleBodyArea` 包住），两半缺一都不算修好。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_body_area.dart';

const _probeKey = Key('body-probe');

/// 渲染「Scaffold + MediaQuery(假内边距)」，返回正文探针的矩形。
///
/// [withArea] = false 时**不**套 `ScheduleBodyArea` —— 那是修复前的样子
/// （正文铺到屏幕底边，含导航栏那一截），用来证明这个组件确实在起作用。
Future<Rect> _pumpBody(
  WidgetTester tester, {
  required EdgeInsets padding,
  bool withArea = true,
  Size size = const Size(400, 700),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, padding: padding),
        child: Scaffold(
          body: withArea
              ? const ScheduleBodyArea(child: SizedBox.expand(key: _probeKey))
              : const SizedBox.expand(key: _probeKey),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getRect(find.byKey(_probeKey));
}

void main() {
  group('ScheduleBodyArea：正文让开底部系统导航栏', () {
    testWidgets('三键导航（底部 48）：正文底边停在导航栏之上', (tester) async {
      final rect = await _pumpBody(
        tester,
        padding: const EdgeInsets.only(bottom: 48),
      );
      expect(
        rect.bottom,
        moreOrLessEquals(700 - 48, epsilon: 0.01),
        reason: '正文底边必须是「屏幕高 − 导航栏高」，否则最后一节被盖住',
      );
      expect(rect.top, moreOrLessEquals(0, epsilon: 0.01));
      expect(rect.height, moreOrLessEquals(700 - 48, epsilon: 0.01));
    });

    testWidgets('不套 ScheduleBodyArea 时正文会铺到屏幕底边（修复前的样子）', (tester) async {
      final rect = await _pumpBody(
        tester,
        padding: const EdgeInsets.only(bottom: 48),
        withArea: false,
      );
      expect(
        rect.bottom,
        moreOrLessEquals(700, epsilon: 0.01),
        reason: '这正是用户报的问题：内容区把导航栏那一截也算进去了',
      );
    });

    testWidgets('顶部状态栏不避（由 AppBar 自己吃）：padding.top 不影响正文顶边', (tester) async {
      final rect = await _pumpBody(
        tester,
        padding: const EdgeInsets.only(top: 24, bottom: 48),
      );
      expect(
        rect.top,
        moreOrLessEquals(0, epsilon: 0.01),
        reason: 'top: false —— 状态栏高度由 AppBar 承担，正文顶边不该再让',
      );
      expect(rect.bottom, moreOrLessEquals(700 - 48, epsilon: 0.01));
    });

    testWidgets('桌面 / 非 edge-to-edge（内边距全 0）：正文照旧铺满，零变化', (tester) async {
      final rect = await _pumpBody(tester, padding: EdgeInsets.zero);
      expect(rect.top, moreOrLessEquals(0, epsilon: 0.01));
      expect(rect.bottom, moreOrLessEquals(700, epsilon: 0.01));
      expect(rect.height, moreOrLessEquals(700, epsilon: 0.01));
    });

    testWidgets('左右内边距（横屏刘海 / 侧边导航栏）沿用 SafeArea 默认：避让', (tester) async {
      final rect = await _pumpBody(
        tester,
        padding: const EdgeInsets.only(left: 30, right: 30, bottom: 48),
      );
      expect(rect.left, moreOrLessEquals(30, epsilon: 0.01));
      expect(rect.right, moreOrLessEquals(400 - 30, epsilon: 0.01));
      expect(rect.bottom, moreOrLessEquals(700 - 48, epsilon: 0.01));
    });
  });

  group('源码守卫：课表页接线', () {
    String read(String path) => File(path).readAsStringSync();

    test('正文用 ScheduleBodyArea 包住（别退回裸 Expanded）', () {
      final src = read(
        'lib/features/ims/schedule/presentation/schedule_screen.dart',
      );
      expect(
        src.contains(
          'Expanded(child: ScheduleBodyArea(child: _buildBody(horizontal)))',
        ),
        isTrue,
        reason: '课表正文必须让开底部导航栏；加载 / 错误 / 空态也走这条路',
      );
    });

    test('两个视图都不得自己再扣一次底部内边距（会让位两次、白留一条）', () {
      for (final path in const [
        'lib/features/ims/schedule/presentation/schedule_grid_view.dart',
        'lib/features/ims/schedule/presentation/schedule_horizontal_view.dart',
      ]) {
        final src = read(path);
        expect(
          src.contains('viewPaddingOf(context).bottom'),
          isFalse,
          reason: '$path 里不许再扣底部系统栏 —— 页面级 ScheduleBodyArea 已让位',
        );
        expect(
          src.contains('paddingOf(context).bottom'),
          isFalse,
          reason: '$path 里不许再扣底部系统栏 —— 页面级 ScheduleBodyArea 已让位',
        );
      }
    });
  });
}
