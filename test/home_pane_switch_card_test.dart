// 换页时**卡片框不许动**（用户 2026-10-09 二十一轮：
// 「为什么现在点击切换页面，会导致整个右侧内容卡片出现位置的水平闪动」）。
//
// 真因：`CardFrame` 原本在 `AnimatedSwitcher` 的 child **里面** → 换页时整张卡片
// 跟着 `SlideTransition` 横移，还被 `Stack` 的边界裁掉一截（被裁那侧的描边整段消失 ——
// 那也是二十轮「圆角处框线断开」的真因）。
//
// ⚠ 为什么单开一个文件：要按生产装配搭宿主 + 逐帧量矩形，塞进 `home_sidebar_test.dart`
// 会与那堆 `pumpSidebar` 可选参数纠缠。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/card_frame.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_gap.dart';

const _pageA = Key('pageA');
const _pageB = Key('pageB');

/// 复刻 `home_screen._buildSidebarBody` 右栏的层级：
/// `Padding → CardFrame → AnimatedSwitcher(内容滑入 + 淡入)`。
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  var _showB = false;

  /// 换到「B 页」（测试从外面驱动；不直接碰受保护的 `setState`）。
  void showB() => setState(() => _showB = true);

  @override
  Widget build(BuildContext context) {
    final gap = cardGapMetricsOf(kCardGapDefault);
    return MaterialApp(
      theme: appDarkTheme,
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(width: 100),
            SizedBox(width: gap.between),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: gap.edge,
                  bottom: gap.edge,
                ),
                child: CardFrame(
                  card: true,
                  radius: 8,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: <Widget>[...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.04, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey<String>(_showB ? 'b' : 'a'),
                      child: ColoredBox(
                        key: _showB ? _pageB : _pageA,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('★ 换页全程：卡片矩形一动不动', (tester) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();

    Rect cardRect() => tester.getRect(find.byKey(cardFrameContainerKey));
    final before = cardRect();

    // 换页：逐帧走完，**每一帧**卡片矩形都必须与换页前完全相同。
    tester.state<_HostState>(find.byType(_Host)).showB();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        cardRect(),
        before,
        reason: '换页第 ${(i + 1) * 20}ms 时卡片矩形变了 —— 卡片跟着滑入动画动了',
      );
    }
    await tester.pumpAndSettle();
    expect(cardRect(), before, reason: '换完后卡片矩形也不许变');
    expect(tester.takeException(), isNull);
  });
}
