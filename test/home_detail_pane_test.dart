import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home/presentation/home_detail_pane.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';

/// 右侧内嵌面板守卫（用户 2026-09-15 裁定第 2 条）：
/// 「点击左侧导航栏后，不是跳转页面，而是直接在右侧显示原跳转页面，并取消原页面的返回按钮」。
///
/// 守四件事：
/// 1. 服务页真的渲染在**面板**里（左侧栏还在，根路由没被替换）；
/// 2. 面板首路由 `canPop == false` → AppBar **不画返回按钮**（要取消的就是它）；
/// 3. 页面内部的二级跳转留在面板内（那时它确实有上一页 → 返回按钮该出现）；
/// 4. `ImsSplashScreen` 那种「首帧后 pushReplacement」的闸门也留在面板内。
void main() {
  HomeServiceEntry entry(String title, Widget Function() builder) =>
      HomeServiceEntry(
        icon: Icons.abc,
        title: title,
        subtitle: '$title 说明',
        group: HomeServiceGroup.ims,
        accent: const Color(0xFFC3282E),
        builder: builder,
        onTap: () {},
      );

  Widget pageB() => Scaffold(
    appBar: AppBar(title: const Text('B 页')),
    body: const Text('B 内容'),
  );

  Widget pageA() => Scaffold(
    appBar: AppBar(title: const Text('A 页')),
    body: Builder(
      builder: (context) => Column(
        children: [
          Text('canPop=${Navigator.of(context).canPop()}'),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => pageB()),
            ),
            child: const Text('进入 B'),
          ),
        ],
      ),
    ),
  );

  Future<void> pumpPane(
    WidgetTester tester,
    HomeServiceEntry current,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(
                width: homeSidebarWidth,
                child: Center(child: Text('侧栏占位')),
              ),
              Expanded(child: HomeDetailPane(entry: current)),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('服务页渲染在面板里，左侧栏与根路由都还在', (tester) async {
    await pumpPane(tester, entry('课程', pageA));

    expect(find.text('A 页'), findsOneWidget);
    expect(find.text('侧栏占位'), findsOneWidget);
    // 面板内容在侧栏右侧（不是覆盖整页）。
    expect(
      tester.getTopLeft(find.text('A 页')).dx,
      greaterThan(homeSidebarWidth),
    );
  });

  testWidgets('面板首路由 canPop=false → 不画返回按钮（第 2 条核心）', (tester) async {
    await pumpPane(tester, entry('课程', pageA));

    expect(find.text('canPop=false'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('页面内二级跳转留在面板内，二级页照常有返回按钮', (tester) async {
    await pumpPane(tester, entry('课程', pageA));

    await tester.tap(find.text('进入 B'));
    await tester.pumpAndSettle();

    expect(find.text('B 内容'), findsOneWidget);
    expect(find.text('侧栏占位'), findsOneWidget, reason: '二级跳转不该盖住侧栏');
    expect(
      find.byType(BackButton),
      findsOneWidget,
      reason: '二级页确实有上一页 → 返回按钮该显示',
    );
  });

  testWidgets('换条目 = 换 Navigator（路由栈重置，不留上一个条目的二级页）', (tester) async {
    await pumpPane(tester, entry('课程', pageA));
    await tester.tap(find.text('进入 B'));
    await tester.pumpAndSettle();
    expect(find.text('B 内容'), findsOneWidget);

    await pumpPane(tester, entry('校历', pageB));
    await tester.pumpAndSettle();

    expect(find.text('B 内容'), findsOneWidget, reason: '新条目自己的首页');
    expect(find.byType(BackButton), findsNothing, reason: '新栈的首路由没有上一页');
    expect(HomeDetailPane.navKeyOf(entry('课程', pageA)), isNot(HomeDetailPane.navKeyOf(entry('校历', pageB))));
  });

  testWidgets('闸门式 pushReplacement（ImsSplashScreen 口径）也留在面板内', (tester) async {
    await pumpPane(tester, entry('成绩', () => const _Gate()));

    expect(find.text('闸门'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('A 页'), findsOneWidget, reason: '闸门换成了功能页');
    expect(
      find.text('侧栏占位'),
      findsOneWidget,
      reason: 'pushReplacement 必须落在面板自己的 Navigator 里，不能替换掉主页',
    );
    expect(find.byType(BackButton), findsNothing);
  });

  test('两处硬编码返回键已改为按 canPop 门控（内嵌时自动消失）', () {
    const paths = [
      'lib/features/ims/menu/presentation/ims_tab_container.dart',
      'lib/features/data_center/presentation/data_center_screen.dart',
    ];
    final unconditional = RegExp(
      r'leading:\s*IconButton\(\s*icon:\s*const Icon\(Icons\.arrow_back\)',
    );
    for (final path in paths) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '找不到 $path');
      final source = file.readAsStringSync();
      expect(
        source.contains('Navigator.of(context).canPop()'),
        isTrue,
        reason: '$path 的返回键应由 canPop 门控（内嵌面板首路由不画返回键）',
      );
      expect(
        unconditional.hasMatch(source),
        isFalse,
        reason: '$path 仍有无条件渲染的返回键',
      );
    }
  });
}

/// 模拟 `ImsSplashScreen`：首帧后 `pushReplacement` 到功能页。
class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('A 页')),
            body: const Text('功能页内容'),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('闸门')));
}
