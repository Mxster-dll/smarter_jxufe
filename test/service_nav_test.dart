/// 「页面跳转缝」的行为守卫（2026-09-20 立 · 架构审查 ⑦）。
///
/// 它替代了两条 feature → feature 的**反向导航边**（zongce → 材料库、student_info → 主页），
/// 那两条边各自与对方的数据依赖构成双向环。这里守三件事：
/// ① 注册 → 打开（push）真的到目标页；② **未注册时不抛、什么都不做**（单测常只 pump 一个
/// 页面、不走组装根）；③ `resetToServiceScreen` = 清栈换页，未注册时退化为 `popUntil(isFirst)`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/navigation/service_nav.dart';

Widget _host(void Function(BuildContext) onTap) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => onTap(context),
        child: const Text('go'),
      ),
    ),
  ),
);

void main() {
  setUp(clearServiceScreens);
  tearDown(clearServiceScreens);

  test('注册表：注册 / 查询 / 快照 / 清空', () {
    expect(hasServiceScreen(kServiceHome), isFalse);
    registerServiceScreen(kServiceHome, () => const Text('首页'));
    expect(hasServiceScreen(kServiceHome), isTrue);
    expect(registeredServiceScreens(), [kServiceHome]);
    clearServiceScreens();
    expect(registeredServiceScreens(), isEmpty);
  });

  testWidgets('已注册 → openServiceScreen 真的 push 到目标页', (tester) async {
    registerServiceScreen(kServiceMaterials, () => const Text('材料库'));
    await tester.pumpWidget(_host((c) => openServiceScreen(c, kServiceMaterials)));
    expect(find.text('材料库'), findsNothing);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('材料库'), findsOneWidget);
  });

  testWidgets('未注册 → 不抛、什么也不做（返回 false）', (tester) async {
    var result = true;
    await tester.pumpWidget(
      _host((c) => result = openServiceScreen(c, 'nope')),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.text('go'), findsOneWidget, reason: '还在原页面上');
  });

  testWidgets('resetToServiceScreen（已注册）= 清栈换页', (tester) async {
    registerServiceScreen(kServiceHome, () => const Text('首页'));
    await tester.pumpWidget(
      _host(
        (c) => Navigator.of(c).push(
          MaterialPageRoute<void>(
            builder: (_) => TextButton(
              onPressed: () => resetToServiceScreen(c, kServiceHome),
              child: const Text('重置'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('go'), findsNothing, reason: '整栈被替换，旧页面不该还在');
  });

  testWidgets('resetToServiceScreen（未注册）退化为回根页', (tester) async {
    await tester.pumpWidget(
      _host(
        (c) => Navigator.of(c).push(
          MaterialPageRoute<void>(
            builder: (_) => TextButton(
              onPressed: () => resetToServiceScreen(c, 'nope'),
              child: const Text('重置'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget, reason: '回到根页面');
  });

  testWidgets('replaceServiceScreen（已注册）= 替换当前页，返回键不再回到旧页', (tester) async {
    registerServiceScreen(kServiceIms, () => const Text('教务'));
    await tester.pumpWidget(
      _host(
        (c) => Navigator.of(c).push(
          MaterialPageRoute<void>(
            builder: (_) => TextButton(
              onPressed: () => replaceServiceScreen(c, kServiceIms),
              child: const Text('换页'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('换页'));
    await tester.pumpAndSettle();
    expect(find.text('教务'), findsOneWidget);
    expect(find.text('换页'), findsNothing, reason: 'pushReplacement 不保留旧页');
  });

  testWidgets('replaceServiceScreen（未注册）不抛、返回 false', (tester) async {
    var result = true;
    await tester.pumpWidget(
      _host((c) {
        Navigator.of(c).push(
          MaterialPageRoute<void>(
            builder: (_) => TextButton(
              onPressed: () => result = replaceServiceScreen(c, 'nope'),
              child: const Text('换页'),
            ),
          ),
        );
      }),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('换页'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.text('换页'), findsOneWidget);
  });
}
