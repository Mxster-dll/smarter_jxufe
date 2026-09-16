/// 设置页「教务会话」卡的 widget 守卫 —— 状态显示 + 按钮真的能按（2026-09-15）。
///
/// 纯逻辑与源码守卫在 `test/ims_token_refresh_test.dart`；这里补的是「渲染出来了吗、
/// 按下去会发生什么」：
/// - 本地有令牌 → 显示掩码 + 账号 + 「已就绪」；
/// - 本地没有令牌 → 「本机暂无令牌」+「未就绪」，且**打开页面不触发换票**；
/// - 按按钮 → 探活判不出（测试环境没有教务网络）时按判定表**照样换票**，
///   换票失败要落在卡片上（而不是静默）并弹 SnackBar。
///
/// ⚠️ 必须 `Hive.init`：设置页其余卡片（校历 / 我的校区 / 平台标识 GUID）会
/// `Hive.openBox`，未初始化时错误会 complete 到无人监听的 future → zone 级未处理异常。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_session.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_session_provider.dart';
import 'package:smarter_jxufe/features/school_calendar/data/calendar_prefs.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/calendar_prefs_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';

/// 假 store：不碰 Hive，可控地给出「本地有 / 没有令牌」。
class _FakeStore implements ImsSessionStore {
  _FakeStore({this.token});

  String? token;

  @override
  Future<String?> read(String account) async => token;

  @override
  Future<void> write(String account, String jsessionId) async =>
      token = jsessionId;

  @override
  Future<String?> migrateLegacy(String account) async => null;

  @override
  Future<void> forget(String account) async => token = null;
}

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('ims_session_card_test');
    Hive.init(dir.path);
    await Hive.openBox<String>('schoolCalendarPrefs');
    await Hive.openBox<String>('myCampusPrefs');
    await Hive.openBox<String>('wxPlatform');
  });

  tearDownAll(() async {
    await Hive.close();
  });

  /// 造一个会话：CAS 解析固定抛异常（测试环境没有教务网络），并记录调用次数。
  ({ImsSession session, _FakeStore store, List<int> renews}) buildSession({
    String? token,
  }) {
    final store = _FakeStore(token: token);
    final renews = <int>[];
    final session = ImsSession(
      account: '2000000000',
      dio: Dio(),
      store: store,
      resolveRedirect: () async {
        renews.add(1);
        throw Exception('测试环境没有 CAS');
      },
    );
    return (session: session, store: store, renews: renews);
  }

  Widget app(ImsSession session) => ProviderScope(
    overrides: [
      myCampusStoreProvider.overrideWith((ref) => MyCampusStore()),
      calendarPrefsStoreProvider.overrideWith((ref) => CalendarPrefsStore()),
      calendarViewerProvider.overrideWith(
        (ref) async => const CalendarViewer(enrollYear: 2026, trainLevel: '本科'),
      ),
      imsSessionProvider.overrideWith((ref) => session),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );

  Future<void> pumpSettings(WidgetTester tester, ImsSession session) async {
    tester.view.physicalSize = const Size(1000, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(session));
    await tester.pumpAndSettle();
  }

  testWidgets('本地有令牌 → 掩码 + 账号 + 已就绪，且打开页面不换票', (tester) async {
    final built = buildSession(token: '3C62725686D8F50E8498135F4273144B');
    await pumpSettings(tester, built.session);

    expect(find.text('教务会话'), findsOneWidget);
    expect(find.text('教务登录令牌（IMS 会话）'), findsOneWidget);
    expect(find.text('刷新登录令牌'), findsOneWidget);
    expect(find.textContaining('3C627256…'), findsOneWidget);
    expect(find.textContaining('账号 2000000000'), findsOneWidget);
    expect(find.text('已就绪'), findsOneWidget);
    // 首屏只 peek：一个请求都不发、更不会顺手换票。
    expect(built.renews, isEmpty);
  });

  testWidgets('本地没有令牌 → 未就绪 + 提示去按按钮，同样不换票', (tester) async {
    final built = buildSession();
    await pumpSettings(tester, built.session);

    expect(find.text('未就绪'), findsOneWidget);
    expect(find.text('本机暂无令牌，点下方按钮获取'), findsOneWidget);
    expect(built.renews, isEmpty);
  });

  testWidgets('按按钮：判不出就换票，失败落在卡片与 SnackBar 上', (tester) async {
    final built = buildSession(token: '3C62725686D8F50E8498135F4273144B');
    await pumpSettings(tester, built.session);

    await tester.ensureVisible(find.text('刷新登录令牌'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新登录令牌'));
    await tester.pumpAndSettle();

    // 测试环境没有教务网络 → 探活 unknown → 判定表要求照样换票。
    expect(built.renews, hasLength(1));
    expect(find.textContaining('最近一次失败'), findsOneWidget);
    expect(find.text('刷新失败，请检查网络后重试'), findsOneWidget);
  });
}
