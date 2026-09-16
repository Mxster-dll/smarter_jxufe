import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_page_transitions.dart';

/// 页面转场守卫（2026-09-16 立）。
///
/// 用户报的问题：「点开培养方案 / 课表 / 成绩 / 毕业学分时，会显示一个由中心向外的
/// 扩张动画」——那是 Flutter 默认的 `ZoomPageTransitionsBuilder`
/// （`page_transitions_theme.dart` 的 `_defaultBuilders` 里 windows/linux 用它，
/// android 用 `PredictiveBackPageTransitionsBuilder`，无预测返回手势时同样回落 zoom）。
///
/// 三组断言：
/// 1. 转场表：桌面 / 安卓 / Fuchsia 走横向共享轴，**表里不含任何 zoom 转场**（回归守卫）；
///    iOS / macOS 保留 Cupertino（回滑返回手势）。
/// 2. 动态行为：进入页从右侧滑入 + 淡入，被压住的页向左让位；落位后位移归零。
/// 3. 源码闸门：IMS 入口闸门不得再换路由（旧实现 pushReplacement → 两次转场 + 闪转圈），
///    且 `main.dart` 必须真的把转场表挂进 `ThemeData`。
void main() {
  group('转场表', () {
    test('桌面 / 安卓 / Fuchsia = 横向共享轴（不是 zoom）', () {
      for (final platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          appPageTransitionsTheme.builders[platform],
          isA<AppPageTransitionsBuilder>(),
          reason: '$platform 必须是横向共享轴：默认的 zoom 就是用户要去掉的'
              '「由中心向外的扩张动画」',
        );
      }
    });

    test('表里不得出现任何 ZoomPageTransitionsBuilder', () {
      expect(
        appPageTransitionsTheme.builders.values
            .whereType<ZoomPageTransitionsBuilder>(),
        isEmpty,
        reason: 'zoom = 从中心放大，正是被否掉的那个效果',
      );
    });

    test('iOS / macOS 保留 Cupertino（回滑返回手势）', () {
      expect(
        appPageTransitionsTheme.builders[TargetPlatform.iOS],
        isA<CupertinoPageTransitionsBuilder>(),
      );
      expect(
        appPageTransitionsTheme.builders[TargetPlatform.macOS],
        isA<CupertinoPageTransitionsBuilder>(),
      );
    });

    test('时长 300ms，进入与返回同长', () {
      const builder = AppPageTransitionsBuilder();
      expect(builder.transitionDuration, appPageTransitionDuration);
      expect(appPageTransitionDuration, const Duration(milliseconds: 300));
      expect(builder.reverseTransitionDuration, builder.transitionDuration);
    });
  });

  group('动态行为', () {
    testWidgets('进入：第二页从右侧滑入并淡入，第一页向左让位', (tester) async {
      await tester.pumpWidget(_app());
      // 两页布局相同（Scaffold > Center > Column[Text, …]），故「第二页的落位」= 第一页现在的 dx。
      final restX = tester.getTopLeft(find.text('第一页')).dx;

      await tester.tap(find.text('打开第二页'));
      await tester.pump(); // 起帧
      await tester.pump(const Duration(milliseconds: 30));

      // —— 结构性断言：只有「位移 + 淡入」，而且位移是纯横向。
      // 缩放就是「从中心向外扩张」（Flutter 默认 zoom 转场），这里必须一个都没有。
      expect(
        find.ancestor(
          of: find.text('第二页'),
          matching: find.byType(ScaleTransition),
        ),
        findsNothing,
        reason: '缩放 = 从中心向外扩张，正是用户要去掉的效果',
      );
      final slides = tester
          .widgetList<SlideTransition>(
            find.ancestor(
              of: find.text('第二页'),
              matching: find.byType(SlideTransition),
            ),
          )
          .toList();
      expect(slides, isNotEmpty, reason: '进场必须是位移驱动');
      expect(
        slides.every((s) => s.position.value.dy == 0),
        isTrue,
        reason: '只允许横向位移（不许上下滑 / 缩放）',
      );

      final earlyOffset = tester.getTopLeft(find.text('第二页')).dx - restX;
      expect(
        earlyOffset,
        greaterThan(8),
        reason: '早段应明显偏右（起点 = 4% 屏宽 = 32px）',
      );
      expect(
        earlyOffset,
        lessThanOrEqualTo(appPageEnterOffsetX * 800 + 1),
        reason: '起点不得超过 4% 屏宽',
      );
      // 被压住的首页在转场中已不参与绘制（Overlay 只画最上面那条不透明路由 →
      // 默认 finder 会跳过它），所以这里**在控件层**读它的让位量，不量屏幕坐标。
      final homeOffsets = tester
          .widgetList<SlideTransition>(
            find.ancestor(
              of: find.text('第一页', skipOffstage: false),
              matching: find.byType(SlideTransition),
            ),
          )
          .map((s) => s.position.value)
          .toList();
      expect(
        homeOffsets.any((o) => o.dx < 0),
        isTrue,
        reason: '被压住的第一页应向左让位（真位移，不改透明度）',
      );
      expect(
        homeOffsets.any((o) => o.dy != 0),
        isFalse,
        reason: '让位同样只能是横向位移',
      );

      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text('第二页'),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, greaterThan(0.0), reason: '转场中应已可见（不是硬切）');
      expect(fade.opacity.value, lessThan(1.0), reason: '转场中应还在淡入');

      await tester.pump(const Duration(milliseconds: 130)); // 中后段
      final midOffset = tester.getTopLeft(find.text('第二页')).dx - restX;
      expect(midOffset, greaterThan(0), reason: '未落位前应仍在最终位置右侧');
      expect(
        midOffset,
        lessThan(earlyOffset / 2),
        reason: '位移应单调收敛（easeOutCubic）',
      );

      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('第二页')).dx,
        closeTo(restX, 0.5),
        reason: '落位后位移必须归零',
      );
      expect(
        tester
            .widget<FadeTransition>(
              find
                  .ancestor(
                    of: find.text('第二页'),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value,
        1.0,
      );
      // 首页此时被第二页完全遮住（不参与绘制），不再断言它的屏幕坐标。
    });

    testWidgets('返回：pop 走同一条转场，结束后第二页离树', (tester) async {
      await tester.pumpWidget(_app());
      final restX = tester.getTopLeft(find.text('第一页')).dx;
      await tester.tap(find.text('打开第二页'));
      await tester.pumpAndSettle();

      final popped = Completer<void>();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(navigator.maybePop().then((_) => popped.complete()));

      // pop 的退场动画要等路由处理完这一帧才起，故逐帧找「向右滑出」的那一帧。
      var movedRight = false;
      for (var i = 0; i < 8 && !movedRight; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        final page = find.text('第二页');
        if (page.evaluate().isEmpty) break;
        if (tester.getTopLeft(page).dx > restX + 1) movedRight = true;
      }
      expect(movedRight, isTrue, reason: '返回时第二页应向右滑出');

      await tester.pumpAndSettle();
      expect(popped.isCompleted, isTrue);
      expect(find.text('第二页'), findsNothing);
      expect(tester.getTopLeft(find.text('第一页')).dx, closeTo(restX, 0.5));
    });
  });

  group('源码闸门', () {
    test('IMS 闸门就地渲染目标页：不再 pushReplacement', () {
      final code = _code(
        'lib/features/ims/splash/presentation/ims_splash_screen.dart',
      );
      expect(
        code.contains('pushReplacement'),
        isFalse,
        reason: '再换一次路由 = 两次转场 + 中间闪一帧转圈，正是「扩张动画」观感的来源之一',
      );
      expect(
        code.contains('ImsTabContainer(initialTab: initialTab)'),
        isTrue,
        reason: '目标页必须由闸门自己渲染',
      );
      expect(code.contains('ImsMenuScreen()'), isTrue);
      expect(
        code.contains('addPostFrameCallback'),
        isFalse,
        reason: '就地渲染后不再有「首帧后 push」的需求',
      );
    });

    test('main.dart 真的把转场表挂进了 ThemeData', () {
      final code = _code('lib/main.dart');
      expect(
        code.contains('pageTransitionsTheme: appPageTransitionsTheme'),
        isTrue,
      );
      expect(code.contains('design/app_page_transitions.dart'), isTrue);
    });

    test('首页侧栏右栏换内容也有转场（且自备撑满的 layoutBuilder）', () {
      final code = _code('lib/features/home/presentation/home_screen.dart');
      expect(
        code.contains('AnimatedSwitcher('),
        isTrue,
        reason: '换服务不许硬切',
      );
      expect(code.contains('duration: appPaneSwitchDuration'), isTrue);
      expect(
        code.contains('fit: StackFit.expand'),
        isTrue,
        reason: 'AnimatedSwitcher 默认 layoutBuilder 是 Stack(alignment: center)、'
            '不撑满 → 右栏内容会缩到中间（看起来像页面变小）',
      );
      expect(
        code.contains('appPaneSwitchOffsetX'),
        isTrue,
        reason: '右栏同样是横向滑入，别改成缩放',
      );
    });
  });
}

/// 读源码并**去掉注释行**后再断言：文档注释里会出现 `pushReplacement` 这类字样，
/// 不去注释会把说明文字当成代码（踩过）。
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((line) {
      final t = line.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    })
    .join('\n');

Widget _app() => MaterialApp(
  theme: ThemeData(useMaterial3: true, pageTransitionsTheme: appPageTransitionsTheme),
  home: Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('第一页'),
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('第二页'),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('打开第二页'),
            ),
          ),
        ],
      ),
    ),
  ),
);
