// 启动冒烟：`SmarterJxUFE` 必须活在 `ProviderScope` 里。
//
// 原文件是 Flutter 模板遗留的计数器测试（`find.text('0')` / `Icons.add`），
// 而本应用从来没有计数器 —— 它自建库起就从没通过过（长期是唯一失败例）。
// 2026-09-16 适配深色模式时 `SmarterJxUFE` 从 StatelessWidget 变成 ConsumerWidget
// （要 `ref.watch(themeModeStoreProvider)`），裸 `pumpWidget(const SmarterJxUFE())`
// 会直接从「断言失败」变成 `StateError` 抛异常 —— 失败方式更隐蔽了。
// 于是把这一例改成真正守契约的冒烟测试：**挂载 + 两套主题 + 默认跟随系统**。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/splash/presentation/splash_screen.dart';
import 'package:smarter_jxufe/main.dart';

void main() {
  late Directory hiveDir;

  // ⚠ 必须先 `Hive.init`：`SmarterJxUFE` 会 watch 外观偏好，其 provider 立刻调
  // `ThemeModeStore.ensureLoaded()` → `Hive.openBox`。Hive 未初始化时那条路径
  // **虽然被 store 自己 try/catch 吞掉了**（实测 ensureLoaded 既不同步抛也不异步抛），
  // 但 Hive 还会把同一条 HiveError 报给 zone → 测试判失败。
  setUpAll(() async {
    hiveDir = Directory.systemTemp.createTempSync('widget_test');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      hiveDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('SmarterJxUFE 在 ProviderScope 里起得来，且挂的是 app_theme 的两套主题', (
    WidgetTester tester,
  ) async {
    // 只泵一帧：`SplashScreen._checkAuth()` 会先 await 真实的 Hive I/O，
    // 在测试的假异步区里那个 future 永远不会完成 → 也就不会排下 500ms 定时器，
    // 不会在收尾时报「A Timer is still pending」。
    await tester.pumpWidget(const ProviderScope(child: SmarterJxUFE()));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme, appLightTheme, reason: '浅色主题必须是 app_theme.dart 那一套');
    expect(app.darkTheme, appDarkTheme, reason: '深色主题必须真的挂上（否则深色模式不生效）');
    expect(app.themeMode, ThemeMode.system, reason: '首次安装默认跟随系统');
    expect(app.debugShowCheckedModeBanner, isFalse);
    expect(app.title, '智慧er江财');

    // 首页 = 启动页。
    expect(find.byType(SplashScreen), findsOneWidget);
  });
}
