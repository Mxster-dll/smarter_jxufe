// 从「数据一览」点卡片开出来的那一页，**顶部不许有导航栏**
// （用户 2026-10-10 二十六轮：「我发现点击主页卡片后的效果还是不对，顶部不应该显示标题栏」）。
//
// 真因：右栏那一格是面板的**首路由**（§44.1.18），从它点卡片是往同一个 Navigator 压
// **第二层**；而 `paneIsRoot` 的判据原本是 `!canPop()` —— 压了第二层就不再成立 →
// `paneAppBar` 照常画出一条完整导航栏 + 返回键。
// 修法：右栏那一个 `PaneScope` 打上 `sidebarPane: true`，这一格上**任何**路由都算首路由。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/home/presentation/home_detail_pane.dart';

/// 一个"像服务页那样"用 `paneAppBar` 的页面。
class _ServiceLikePage extends StatelessWidget {
  const _ServiceLikePage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: paneAppBar(context, title: Text(title)),
    body: PaneBody(
      actions: const [Text('动作')],
      child: Center(child: Text('$title 内容')),
    ),
  );
}

Widget host({required bool sidebarPane}) =>
    MaterialApp(
      theme: appDarkTheme,
      home: HomeDetailPane(
        paneKey: 'probe',
        sidebarPane: sidebarPane,
        builder: () => const _ServiceLikePage(title: '首路由'),
      ),
    );

void main() {
  testWidgets('★ 侧栏右栏那一格：压了第二层也不画导航栏', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late BuildContext pageContext;
    await tester.pumpWidget(
      host(sidebarPane: true),
    );
    pageContext = tester.element(find.text('首路由 内容'));
    await tester.pumpAndSettle();

    // ① 首路由：本来就不该有导航栏
    expect(
      find.byType(AppBar),
      findsNothing,
      reason: '侧栏右栏的首路由不该有导航栏',
    );

    // ② 往上压一层（= 从概览点卡片）
    Navigator.of(pageContext).push(
      MaterialPageRoute<void>(
        builder: (_) => const _ServiceLikePage(title: '第二层'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第二层 内容'), findsOneWidget, reason: '第二层应当开出来了');
    expect(
      find.byType(AppBar),
      findsNothing,
      reason: '侧栏右栏上的第二层**也不许**有导航栏（用户二十六轮报的就是这条）',
    );
    expect(
      find.byType(BackButton),
      findsNothing,
      reason: '连带那个自行冒出来的返回键也不许有',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('对照：普通面板（不传 sidebarPane）的二级页照旧画导航栏', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(sidebarPane: false));
    final pageContext = tester.element(find.text('首路由 内容'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing, reason: '首路由仍不画');

    Navigator.of(pageContext).push(
      MaterialPageRoute<void>(
        builder: (_) => const _ServiceLikePage(title: '二级页'),
      ),
    );
    await tester.pumpAndSettle();

    // 这一路是「内嵌服务页 → 课程详情」那种情形：二级页**要有**导航栏 + 返回键
    expect(
      find.byType(AppBar),
      findsOneWidget,
      reason: '普通面板里的二级页必须保留导航栏（老行为不许被这轮改掉）',
    );
  });
}
